#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
import re

def read_file(file_path):
    """读取文件并解析数据（空白分隔）"""
    data = {}
    header = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            first_line = f.readline().strip()
            if not first_line:
                print("错误: 文件为空或第一行没有表头")
                return None, None
            header = first_line.split()
            for line in f:
                line = line.strip()
                if not line:
                    continue
                values = line.split()
                if len(values) != len(header):
                    # 跳过列数不一致的行
                    continue
                for i, value in enumerate(values):
                    col = header[i]
                    if col not in data:
                        data[col] = []
                    data[col].append(value)
    except Exception as e:
        print(f"读取文件时出错: {e}")
        return None, None
    return header, data

def is_float(x: str) -> bool:
    try:
        float(x)
        return True
    except Exception:
        return False

def calculate_b10(column_data):
    """
    计算单列 B10:
      proportion = 频率(phi<0.01)
      B10 = 0.01 / proportion  (proportion=0 时返回 Inf)
    """
    count_lt = 0
    total_valid = 0
    for v in column_data:
        if is_float(v):
            total_valid += 1
            if float(v) < 0.01:
                count_lt += 1
    if total_valid == 0:
        return float('inf'), 0.0, 0, 0
    proportion = count_lt / total_valid
    b10 = (0.01 / proportion) if proportion > 0 else float('inf')
    return b10, proportion, count_lt, total_valid

# 兼容 phi_ 和 phi: 的列名（大小写不敏感）
PHI_PREFIX_RE = re.compile(r'^phi[:_]', re.IGNORECASE)

def is_phi_column(colname: str) -> bool:
    return PHI_PREFIX_RE.match(colname) is not None

def scenario_name_from_col(colname: str) -> str:
    # 去掉前缀 'phi_' 或 'phi:'（长度皆为4）
    return colname[4:] if len(colname) >= 5 else colname

def main():
    if len(sys.argv) != 3:
        print("用法: python cal_b10.py <输入文件> <输出文件>")
        print("示例: python cal_b10.py input.txt output.txt")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    if not os.path.exists(input_file):
        print(f"错误: 输入文件不存在: {input_file}")
        sys.exit(1)

    print(f"正在读取文件: {input_file}")
    header, data = read_file(input_file)
    if header is None or data is None:
        print("读取文件失败")
        sys.exit(1)

    print(f"找到 {len(header)} 列")
    # 选出 phi_* 或 phi:* 列
    phi_columns = [c for c in header if is_phi_column(c)]
    if not phi_columns:
        print("未找到以 'phi_' 或 'phi:' 开头的列")
        sys.exit(1)

    print(f"找到 {len(phi_columns)} 个 phi 列: {phi_columns}")

    # 计算并汇总
    results = []
    for col in phi_columns:
        scen = scenario_name_from_col(col)
        b10, prop, cnt, tot = calculate_b10(data.get(col, []))
        b10_disp = f"{b10:.6f}" if b10 != float('inf') else "Inf"
        print(f"计算 {col}: B10={b10_disp}  (<0.01: {cnt}/{tot})")
        results.append({
            "scenario": scen,
            "b10": b10
        })

    # 场景名排序输出
    results.sort(key=lambda x: x["scenario"])
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("Scenario\tB10\n")
            for r in results:
                b10_disp = f"{r['b10']:.6f}" if r['b10'] != float('inf') else "Inf"
                f.write(f"{r['scenario']}\t{b10_disp}\n")
        print(f"\n结果已保存到: {output_file}")
        print("\n最终结果:")
        print("Scenario\tB10")
        print("-" * 20)
        for r in results:
            b10_disp = f"{r['b10']:.6f}" if r['b10'] != float('inf') else "Inf"
            print(f"{r['scenario']}\t{b10_disp}")
    except Exception as e:
        print(f"保存文件时出错: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
