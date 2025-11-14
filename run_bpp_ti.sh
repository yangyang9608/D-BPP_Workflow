#!/bin/bash

# 设置默认值
POINTS=16

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--points)
            POINTS="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项] <ctl文件>"
            echo "选项:"
            echo "  -p, --points NUM    指定生成的文件数量 (默认: 16)"
            echo "  -h, --help         显示帮助信息"
            exit 0
            ;;
        *)
            CTL_FILE="$1"
            shift
            ;;
    esac
done

# 检查是否提供了ctl文件名
if [ -z "$CTL_FILE" ]; then
    echo "错误: 必须提供ctl文件名"
    echo "用法: $0 [选项] <ctl文件>"
    exit 1
fi

# 获取基础文件名（不带后缀）
base_name="${CTL_FILE%.ctl}"

echo "使用ctl文件: $CTL_FILE"
echo "生成文件数量: $POINTS"

# 第一步：生成带编号的文件
echo "生成${base_name}.ctl.1到${base_name}.ctl.${POINTS}文件..."
bpp --bfdriver "$CTL_FILE" --points "$POINTS"

# 第二步：替换每个文件中的job名称
echo "替换文件中的job名称..."
for i in $(seq 1 "$POINTS"); do
    filename="${base_name}.ctl.$i"
    new_job="${base_name}-$i.job"
    
    if [ -f "$filename" ]; then
        sed -i "s/${base_name}\.job/${base_name}-$i.job/g" "$filename"
        echo "已处理: $filename -> 替换为 $new_job"
    else
        echo "警告: 文件 $filename 不存在"
    fi
done

# 第三步：批量提交任务到后台
echo "提交${POINTS}个任务到后台..."
for i in $(seq 1 "$POINTS"); do
    filename="${base_name}.ctl.$i"
    if [ -f "$filename" ]; then
        nohup bpp -cfile "$filename" > "${base_name}-$i.out" 2>&1 &
        echo "已提交: $filename (PID: $!)"
    else
        echo "警告: 文件 $filename 不存在，跳过"
    fi
done

echo "所有任务已提交到后台运行"
echo "输出日志: ${base_name}-*.out"
echo "可以使用以下命令查看任务状态:"
echo "  jobs"
echo "  ps aux | grep bpp"
echo "  tail -f ${base_name}-1.out  # 查看第一个任务的输出"
