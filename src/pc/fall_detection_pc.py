# -*- coding: utf-8 -*-
import serial
import serial.tools.list_ports
import struct
import math
import tkinter as tk
from tkinter import messagebox, ttk, filedialog
import csv
import os
import threading
import time
import random
import queue
from collections import deque
from datetime import datetime
from enum import Enum

import matplotlib
matplotlib.use("TkAgg")
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

try:
    import winsound
    HAS_WINSOUND = True
except ImportError:
    HAS_WINSOUND = False

SERIAL_PORT = 'COM10'
BAUD_RATE = 115200
USE_SIMULATION = False

CSV_FILE = 'fall_data.csv'
SAMPLE_INTERVAL = 0.02
BUFFER_SIZE = 250

TH_FREEFALL = 0.6
TH_IMPACT = 1.4
IMPACT_HOLD = 0.25
IMPACT_LOST = 1.0
SILENT_HOLD = 3.0


class Status(Enum):
    NORMAL = "Normal"
    FREEFALL = "FreeFall"
    IMPACT = "Impact"
    ALARM = "Alarm"
    SILENT = "Silent"


current_svm = 1.0
current_status = Status.NORMAL
device_id = "001"

svm_buffer = deque([1.0] * BUFFER_SIZE, maxlen=BUFFER_SIZE)

data_queue = queue.Queue(maxsize=1000)
stop_event = threading.Event()

csv_lock = threading.Lock()
ser = None
ser_lock = threading.Lock()


def _find_serial_port():
    hc05 = None
    bluetooth_candidates = []

    for port in serial.tools.list_ports.comports():
        desc = str(port.description)
        if "HC-05" in desc:
            hc05 = (port.device, desc)
            break
        if "Bluetooth" in desc:
            bluetooth_candidates.append((port.device, desc))

    if hc05:
        print(f"[Serial] Found HC-05: {hc05[0]} ({hc05[1]})")
        return hc05[0]
    if bluetooth_candidates:
        p = bluetooth_candidates[0]
        print(f"[Serial] Using first Bluetooth port: {p[0]} ({p[1]})")
        return p[0]
    print(f"[Serial] Bluetooth not found, using fallback: {SERIAL_PORT}")
    return SERIAL_PORT


def open_serial(retries=3):
    if USE_SIMULATION:
        return None

    target_port = _find_serial_port()
    for attempt in range(1, retries + 1):
        try:
            s = serial.Serial(
                target_port, BAUD_RATE,
                timeout=1, write_timeout=1
            )
            try:
                s.reset_input_buffer()
                s.reset_output_buffer()
            except Exception:
                pass
            print(f"[Serial] opened successfully: {target_port}")
            return s
        except Exception as e:
            print(f"[Serial] open attempt {attempt} failed: {e}")
            time.sleep(0.5)

    print("[Serial] could not open any port, running without serial")
    return None


class FallStateMachine:
    def __init__(self):
        self.state = Status.NORMAL
        self.t_impact = None
        self.t_alarm = None
        self.t_last_impact = None
        self.peak_svm = 0.0
        self.from_freefall = False

    def update(self, svm, now):
        should_alarm = False

        if self.state == Status.NORMAL:
            if svm < TH_FREEFALL:
                self.state = Status.FREEFALL
            elif svm > TH_IMPACT:
                self.state = Status.IMPACT
                self.t_impact = now
                self.t_last_impact = now
                self.peak_svm = svm
                self.from_freefall = False

        elif self.state == Status.FREEFALL:
            if svm > TH_IMPACT:
                self.state = Status.IMPACT
                self.t_impact = now
                self.t_last_impact = now
                self.peak_svm = svm
                self.from_freefall = True
            elif svm >= TH_FREEFALL:
                self.state = Status.NORMAL

        elif self.state == Status.IMPACT:
            if svm > self.peak_svm:
                self.peak_svm = svm
            if svm > TH_IMPACT:
                self.t_last_impact = now

            if (now - self.t_impact) >= IMPACT_HOLD:
                if self.from_freefall:
                    self.state = Status.ALARM
                    self.t_alarm = now
                    should_alarm = True
                else:
                    self.state = Status.NORMAL
                    self.t_impact = None
                    self.peak_svm = 0.0
            elif (now - self.t_last_impact) > IMPACT_LOST:
                self.state = Status.NORMAL
                self.t_impact = None
                self.from_freefall = False
                self.peak_svm = 0.0

        elif self.state == Status.ALARM:
            if svm > TH_IMPACT:
                self.t_last_impact = now
            if self.t_last_impact and (now - self.t_last_impact) > SILENT_HOLD:
                self.state = Status.NORMAL
                self.t_alarm = None
                self.t_impact = None
                self.peak_svm = 0.0
                self.from_freefall = False

        return self.state, should_alarm

    def reset(self):
        self.state = Status.NORMAL
        self.t_impact = None
        self.t_alarm = None
        self.t_last_impact = None
        self.peak_svm = 0.0
        self.from_freefall = False


fsm = FallStateMachine()

alarm_window = None
blink_job = None
blink_state = [False]
sound_stop = threading.Event()
sound_thread = None
last_alarm_time = [0.0]

ui_ready = threading.Event()


def calculate_svm(ax, ay, az):
    ax_g = ax / 4096.0
    ay_g = ay / 4096.0
    az_g = az / 4096.0
    return math.sqrt(ax_g * ax_g + ay_g * ay_g + az_g * az_g)


def init_csv():
    if not os.path.exists(CSV_FILE):
        try:
            with csv_lock:
                with open(CSV_FILE, 'w', newline='', encoding='utf-8-sig') as f:
                    writer = csv.writer(f)
                    writer.writerow(['Time', 'SVM(g)', 'Status', 'Location', 'DeviceID'])
        except Exception as e:
            print("[CSV] init failed:", e)


def append_csv(svm, status, location):
    try:
        with csv_lock:
            with open(CSV_FILE, 'a', newline='', encoding='utf-8-sig') as f:
                writer = csv.writer(f)
                writer.writerow([
                    datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                    "{:.3f}".format(svm),
                    status.value,
                    location,
                    device_id,
                ])
    except Exception as e:
        print("[CSV] write failed:", e)


def simulate_data():
    print("[Sim] simulation thread started")
    next_fall = time.time() + 10
    fall_phase = None
    phase_start = 0

    while not stop_event.is_set():
        now = time.time()

        if now >= next_fall and fall_phase is None:
            fall_phase = 'freefall'
            phase_start = now
            print("[Sim] >>> simulating FALL <<<")

        if fall_phase == 'freefall':
            if now - phase_start < 0.3:
                svm = random.uniform(0.1, 0.4)
            else:
                fall_phase = 'impact'
                phase_start = now
                svm = random.uniform(2.6, 3.5)
        elif fall_phase == 'impact':
            if now - phase_start < 2.5:
                svm = random.uniform(2.6, 3.8)
            else:
                fall_phase = None
                next_fall = now + 30
                svm = random.uniform(0.9, 1.1)
        else:
            svm = random.uniform(0.9, 1.1)

        try:
            data_queue.put_nowait((svm, now))
        except queue.Full:
            pass

        time.sleep(SAMPLE_INTERVAL)


def read_serial():
    global ser
    if ser is None:
        print("[Serial] no port, read thread not started")
        return

    print("[Serial] read thread started")
    consecutive_errors = 0
    rx_buffer = bytearray()

    while not stop_event.is_set():
        with ser_lock:
            s = ser
        if s is None or not s.is_open:
            time.sleep(0.5)
            continue

        try:
            chunk = s.read(128)
            if not chunk:
                consecutive_errors = 0
                continue

            rx_buffer.extend(chunk)

            while True:
                start = rx_buffer.find(b'\xaa\xbb')
                if start == -1:
                    if len(rx_buffer) > 512:
                        rx_buffer.clear()
                    break
                
                end = rx_buffer.find(b'\xcc\xdd', start + 2)
                if end == -1:
                    if start > 0:
                        del rx_buffer[:start]
                    break

                frame = bytes(rx_buffer[start:end + 2])
                del rx_buffer[:end + 2]

                if len(frame) < 8:
                    continue

                ax, ay, az = struct.unpack('>3h', frame[2:8])
                svm = calculate_svm(ax, ay, az)

                try:
                    data_queue.put_nowait((svm, time.time()))
                except queue.Full:
                    pass

            consecutive_errors = 0

        except Exception as e:
            consecutive_errors += 1
            print(f"[Serial] read error ({consecutive_errors}): {e}")
            time.sleep(0.2)

            if consecutive_errors >= 5:
                print("[Serial] too many errors, attempting reconnect...")
                try:
                    with ser_lock:
                        if ser is not None:
                            try:
                                ser.close()
                            except Exception:
                                pass
                        ser = None
                    time.sleep(1.0)
                    new_ser = open_serial(retries=2)
                    with ser_lock:
                        ser = new_ser
                    rx_buffer.clear()
                    consecutive_errors = 0
                except Exception as ee:
                    print("[Serial] reconnect failed:", ee)
                    time.sleep(1.0)


root = tk.Tk()
root.title("Fall Detection System v2.0")
root.geometry("640x780")

top_frame = tk.Frame(root)
top_frame.pack(pady=8, fill=tk.X, padx=12)

label_svm = tk.Label(top_frame, text="SVM: 1.00 g",
                     font=("Consolas", 26, "bold"))
label_svm.pack(pady=4)

label_status = tk.Label(top_frame, text="Status: Normal",
                        font=("Arial", 18, "bold"), fg="green")
label_status.pack(pady=4)

label_loc_title = tk.Label(top_frame, text="Select Location:",
                           font=("Arial", 11))
label_loc_title.pack()
location_var = tk.StringVar(value="Dorm A 302")
location_combo = ttk.Combobox(
    top_frame, textvariable=location_var, font=("Arial", 11),
    values=["Dorm A 302", "Canteen 1F", "Library 2F",
            "Playground", "Teaching Building 3F"])
location_combo.pack(pady=2)

label_location = tk.Label(top_frame, text="Location: Dorm A 302",
                          font=("Arial", 11))
label_location.pack(pady=2)

label_device = tk.Label(top_frame, text="Device ID: " + device_id,
                        font=("Arial", 11))
label_device.pack(pady=2)

btn_frame = tk.Frame(root)
btn_frame.pack(pady=4)


def manual_alarm():
    trigger_alarm(current_svm)


def reset_alarm():
    fsm.reset()
    print("[UI] manually reset")


def view_history():
    if not os.path.exists(CSV_FILE):
        messagebox.showinfo("History", "No records yet.")
        return
    win = tk.Toplevel(root)
    win.title("Alarm History")
    win.geometry("620x400")

    cols = ('Time', 'SVM(g)', 'Status', 'Location', 'DeviceID')
    tree = ttk.Treeview(win, columns=cols, show='headings')
    for c in cols:
        tree.heading(c, text=c)
        tree.column(c, width=110, anchor='center')
    tree.pack(fill=tk.BOTH, expand=True)

    try:
        with csv_lock:
            with open(CSV_FILE, 'r', encoding='utf-8-sig') as f:
                reader = csv.reader(f)
                next(reader, None)
                for row in reader:
                    if len(row) == 5:
                        tree.insert('', tk.END, values=row)
    except Exception as e:
        messagebox.showerror("History", "Read failed: " + str(e))

    def export():
        path = filedialog.asksaveasfilename(
            defaultextension='.csv',
            filetypes=[('CSV', '*.csv')])
        if path:
            try:
                with csv_lock:
                    with open(CSV_FILE, 'r', encoding='utf-8-sig') as src, \
                         open(path, 'w', newline='', encoding='utf-8-sig') as dst:
                        dst.write(src.read())
                messagebox.showinfo("Export", "Saved to: " + path)
            except Exception as e:
                messagebox.showerror("Export", "Failed: " + str(e))

    tk.Button(win, text="Export...", command=export).pack(pady=6)


tk.Button(btn_frame, text="Manual Alarm (Space)", width=18,
          command=manual_alarm).grid(row=0, column=0, padx=4)
tk.Button(btn_frame, text="Reset", width=10,
          command=reset_alarm).grid(row=0, column=1, padx=4)
tk.Button(btn_frame, text="History", width=10,
          command=view_history).grid(row=0, column=2, padx=4)

bottom_frame = tk.Frame(root)
bottom_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=8)

fig = Figure(figsize=(6, 3.2), dpi=100)
ax = fig.add_subplot(111)
ax.set_title("SVM Waveform (last 5s)")
ax.set_xlabel("Sample")
ax.set_ylabel("SVM (g)")
ax.set_ylim(0, 4)
ax.axhline(y=TH_IMPACT, color='r', linestyle='--',
           label='Impact (%.1f g)' % TH_IMPACT)
ax.axhline(y=TH_FREEFALL, color='orange', linestyle='--',
           label='FreeFall (%.1f g)' % TH_FREEFALL)
ax.legend(loc='upper right', fontsize=8)
line, = ax.plot([], [], 'b-', linewidth=1)

canvas = FigureCanvasTkAgg(fig, master=bottom_frame)
canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)


def sound_loop():
    while not sound_stop.is_set():
        if HAS_WINSOUND:
            try:
                winsound.Beep(1000, 200)
            except Exception:
                pass
        else:
            print("\a", end="", flush=True)
            time.sleep(0.2)
        time.sleep(0.05)


def start_sound():
    global sound_thread
    sound_stop.clear()
    if sound_thread is None or not sound_thread.is_alive():
        sound_thread = threading.Thread(target=sound_loop, daemon=True)
        sound_thread.start()


def stop_sound():
    sound_stop.set()


def close_alarm_window():
    global alarm_window, blink_job

    stop_sound()

    if blink_job is not None:
        try:
            root.after_cancel(blink_job)
        except Exception:
            pass
        blink_job = None

    if alarm_window is not None:
        try:
            if alarm_window.winfo_exists():
                alarm_window.destroy()
        except Exception:
            pass
    alarm_window = None
    blink_state[0] = False


def blink_alarm():
    global blink_job

    if alarm_window is None:
        blink_job = None
        return

    try:
        if not alarm_window.winfo_exists():
            blink_job = None
            return
    except Exception:
        blink_job = None
        return

    blink_state[0] = not blink_state[0]
    bg = "red" if blink_state[0] else "white"
    fg = "white" if blink_state[0] else "red"

    try:
        alarm_window.configure(bg=bg)
        for child in alarm_window.winfo_children():
            try:
                child.configure(bg=bg, fg=fg)
            except Exception:
                pass
    except Exception:
        pass

    blink_job = root.after(400, blink_alarm)


def _trigger_alarm_ui(svm):
    global alarm_window

    loc = location_var.get()
    msg = ("Fall detected!\n\n"
           f"Device ID: {device_id}\n"
           f"Location : {loc}\n"
           f"Time     : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
           f"SVM      : {svm:.2f} g")
    print("[Alarm]", msg.replace("\n", " | "))

    try:
        append_csv(svm, Status.ALARM, loc)
    except Exception as e:
        print("[CSV] append failed (ignored):", e)

    close_alarm_window()

    alarm_window = tk.Toplevel(root)
    alarm_window.title("SOS")
    alarm_window.configure(bg="red")
    alarm_window.attributes("-topmost", True)
    alarm_window.protocol("WM_DELETE_WINDOW", close_alarm_window)

    w, h = 560, 380
    x = root.winfo_x() + (root.winfo_width() - w) // 2
    y = root.winfo_y() + (root.winfo_height() - h) // 2
    alarm_window.geometry(f"{w}x{h}+{x}+{y}")
    alarm_window.resizable(False, False)

    tk.Label(alarm_window, text="\u26a0 FALL DETECTED \u26a0",
             font=("Arial", 26, "bold"),
             fg="white", bg="red").pack(pady=(24, 8))

    tk.Label(alarm_window, text=msg,
             font=("Consolas", 14),
             fg="white", bg="red", justify="left").pack(pady=10)

    tk.Button(alarm_window, text="OK",
              font=("Arial", 16, "bold"),
              width=10, height=2,
              bg="white", fg="red",
              command=close_alarm_window).pack(pady=16)

    blink_state[0] = False
    blink_alarm()
    start_sound()


def trigger_alarm(svm):
    if not ui_ready.is_set():
        pass
    try:
        root.after(0, lambda: _trigger_alarm_ui(svm))
    except Exception as e:
        print("[Alarm] schedule failed:", e)


def update_ui():
    global current_svm, current_status

    consumed = 0
    while True:
        try:
            svm, ts = data_queue.get_nowait()
        except queue.Empty:
            break

        current_svm = svm
        svm_buffer.append(svm)

        status, should_alarm = fsm.update(svm, ts)
        current_status = status

        if should_alarm and (ts - last_alarm_time[0]) > 1.0:
            last_alarm_time[0] = ts
            peak = fsm.peak_svm if fsm.peak_svm > 0 else svm
            trigger_alarm(peak)

        consumed += 1
        if consumed > 500:
            break

    label_svm.config(text="SVM: {:.2f} g".format(current_svm))
    label_status.config(text="Status: " + current_status.value)
    label_location.config(text="Location: " + location_var.get())

    color_map = {
        Status.NORMAL:   "green",
        Status.FREEFALL: "orange",
        Status.IMPACT:   "red",
        Status.ALARM:    "red",
        Status.SILENT:   "purple",
    }
    label_status.config(fg=color_map.get(current_status, "black"))

    y_data = list(svm_buffer)
    if y_data:
        x_data = list(range(len(y_data)))
        line.set_data(x_data, y_data)
        ax.set_xlim(0, max(1, len(y_data)))
    canvas.draw_idle()

    if not stop_event.is_set():
        root.after(80, update_ui)


def on_space(event):
    trigger_alarm(current_svm)


def on_closing():
    print("[App] closing...")
    stop_event.set()
    close_alarm_window()
    with ser_lock:
        if ser is not None:
            try:
                if ser.is_open:
                    ser.close()
            except Exception:
                pass
    time.sleep(0.1)
    try:
        root.destroy()
    except Exception:
        pass


root.protocol("WM_DELETE_WINDOW", on_closing)
root.bind('<space>', on_space)


def start():
    global ser

    init_csv()

    ser = open_serial()

    if USE_SIMULATION or ser is None:
        if USE_SIMULATION:
            print("[App] Simulation mode started")
        else:
            print("[App] Serial unavailable -> falling back to simulation")
        threading.Thread(target=simulate_data, daemon=True).start()
    else:
        print("[App] Serial mode started")
        threading.Thread(target=read_serial, daemon=True).start()

    ui_ready.set()
    update_ui()
    root.mainloop()


if __name__ == '__main__':
    start()