# ==========================================
# MPU6050 跌倒检测系统 - Vivado 自动化构建脚本
# ==========================================

# 1. 定义工程名称和路径 (建议使用绝对路径，且不要有中文和空格)
set proj_name "fall_detection"
set proj_dir  "D:/Vivado_Projects/fall_detection"

# 2. 定义源文件路径 (如果脚本和代码在同一个文件夹，可以用相对路径)
# 请把这里的路径换成你代码实际所在的文件夹
set src_dir "D:/Vivado_Projects/source_code"

# 3. 定义器件型号 (Nexys A7 100T)
set part_name "xc7a100tcsg324-1"

# ==========================================
# 开始执行
# ==========================================
puts "------------------------------------------------"
puts "正在创建工程: $proj_name"
puts "------------------------------------------------"

# 清理旧的同名工程（如果存在）
if {[file exists $proj_dir]} {
    puts "检测到旧工程，正在删除..."
    file delete -force $proj_dir
}

# 创建工程
create_project $proj_name $proj_dir -part $part_name -force

# 添加所有 Verilog 设计文件
add_files -norecurse -fileset sources_1 [list \
    "$src_dir/top.v" \
    "$src_dir/i2c_master.v" \
    "$src_dir/mpu6050_ctrl.v" \
    "$src_dir/data_pack.v" \
    "$src_dir/uart_tx.v" \
]

# 添加约束文件
add_files -norecurse -fileset constrs_1 [list \
    "$src_dir/top.xdc" \
]

# 设置顶层模块
set_property top top [current_fileset]

# 更新编译顺序（非常重要，否则可能找不到顶层）
update_compile_order -fileset sources_1

puts "------------------------------------------------"
puts "工程创建完成，开始综合..."
puts "------------------------------------------------"

# ==========================================
# 运行综合 (Synthesis)
# ==========================================
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: 综合失败，请检查代码！"
    exit 1
}
puts "综合成功！"

# ==========================================
# 运行实现 (Implementation)
# ==========================================
puts "------------------------------------------------"
puts "开始实现 (布局布线)..."
puts "------------------------------------------------"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: 实现失败，请检查约束或时序！"
    exit 1
}
puts "实现及生成 bit 流成功！"

# ==========================================
# 生成用于固化的 .bin 文件
# ==========================================
puts "------------------------------------------------"
puts "正在生成 Flash 固化用的 .bin 文件..."
puts "------------------------------------------------"

set bit_file "$proj_dir/$proj_name.runs/impl_1/top.bit"
set bin_file "$proj_dir/$proj_name.runs/impl_1/top.bin"

# 写入 cfgmem 命令
write_cfgmem -format bin -size 16 -interface SPIx4 -loadbit "up 0x00000000 $bit_file" -file $bin_file

puts "------------------------------------------------"
puts "🎉 所有流程执行完毕！"
puts "Bit文件: $bit_file"
puts "Bin文件: $bin_file"
puts "------------------------------------------------"