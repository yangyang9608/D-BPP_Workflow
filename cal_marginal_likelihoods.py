#!/usr/bin/env python3
import sys
import os
import subprocess
import re
import glob

def parse_betaweights_file(betaweights_file):
    """解析betaweights.csv文件，构建beta到weight的映射"""
    beta_weight_map = {}
    
    try:
        with open(betaweights_file, 'r') as f:
            lines = f.readlines()
        
        # 跳过表头
        for line in lines[1:]:
            line = line.strip()
            if line:
                parts = line.split(',')
                if len(parts) >= 2:
                    try:
                        beta = float(parts[0])
                        weight = float(parts[1])
                        beta_weight_map[beta] = weight
                    except ValueError:
                        print(f"警告: 跳过无效行: {line}")
                        continue
        
        print(f"从 {betaweights_file} 中读取到 {len(beta_weight_map)} 个beta权重对")
        
        # 检查权重和是否为1（验证数据）
        total_weight = sum(beta_weight_map.values())
        
        
        return beta_weight_map
    
    except Exception as e:
        print(f"读取betaweights文件失败: {e}")
        return None

def get_bfbeta_values_with_filenames(out_files_pattern):
    """获取BFbeta信息并关联文件名"""
    bfbeta_data = []
    
    # 获取所有匹配的文件
    out_files = glob.glob(out_files_pattern)
    if not out_files:
        print(f"错误: 没有找到匹配 {out_files_pattern} 的文件")
        return None
    
    print(f"找到 {len(out_files)} 个.out文件")
    
    for out_file in out_files:
        try:
            with open(out_file, 'r') as f:
                content = f.read()
            
            # 在文件内容中查找BFbeta和E_b(lnf(X))信息
            patterns = [
                r'BFbeta\s*=\s*([0-9.]+).*?E_b\(lnf\(X\)\)\s*=\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)',
                r'beta\s*=\s*([0-9.]+).*?E_b\(lnf\(X\)\)\s*=\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)'
            ]
            
            for pattern in patterns:
                match = re.search(pattern, content, re.DOTALL)
                if match:
                    beta = float(match.group(1))
                    elnfx = float(match.group(2))
                    bfbeta_data.append((out_file, beta, elnfx))
                    print(f"从文件 {os.path.basename(out_file)} 中提取: beta={beta:.6f}, ElnfX={elnfx:.2f}")
                    break
            else:
                print(f"警告: 在文件 {os.path.basename(out_file)} 中未找到BFbeta信息")
                
        except Exception as e:
            print(f"读取文件 {out_file} 失败: {e}")
    
    print(f"总共解析到 {len(bfbeta_data)} 个BFbeta条目")
    return bfbeta_data

def calculate_marginal_likelihood(bfbeta_data, beta_weight_map):
    """计算边际似然值"""
    marginal_likelihood = 0.0
    contributions = []
    
    print("\n计算边际似然值:")
    print("文件名\t\t\tbeta\t\tweight\t\tElnfX\t\tcontribution")
    print("-" * 90)
    
    # 检查是否所有beta值都找到了对应的权重
    missing_betas = []
    
    for filename, beta, elnfx in bfbeta_data:
        if beta in beta_weight_map:
            weight = beta_weight_map[beta]
            contribution = weight * elnfx / 2
            marginal_likelihood += contribution
            contributions.append((filename, beta, weight, elnfx, contribution))
            
            short_filename = os.path.basename(filename)
            print(f"{short_filename:20} {beta:10.6f} {weight:10.6f} {elnfx:15.2f} {contribution:15.2f}")
        else:
            missing_betas.append(beta)
            short_filename = os.path.basename(filename)
            print(f"警告: 在文件 {short_filename} 中未找到beta={beta:.6f}对应的权重")
    
    if missing_betas:
        print(f"\n未找到权重的beta值: {missing_betas}")
    
    return marginal_likelihood, contributions

def main():
    """主函数"""
    if len(sys.argv) != 4:
        print("用法: python calc_marginal_likelihood.py <betaweights.csv> <out_files_pattern> <output_file>")
        print("示例: python calc_marginal_likelihood.py model.betaweights.csv '*.out.*' marginal_likelihood.txt")
        sys.exit(1)
    
    betaweights_file = sys.argv[1]
    out_files_pattern = sys.argv[2]
    output_file = sys.argv[3]
    
    # 检查文件是否存在
    if not os.path.exists(betaweights_file):
        print(f"错误: betaweights文件 '{betaweights_file}' 不存在")
        sys.exit(1)
    
    # 解析betaweights文件
    beta_weight_map = parse_betaweights_file(betaweights_file)
    if not beta_weight_map:
        print("解析betaweights文件失败")
        sys.exit(1)
    
    # 获取BFbeta信息（逐个文件处理以确保有文件名）
    bfbeta_data = get_bfbeta_values_with_filenames(out_files_pattern)
    if not bfbeta_data:
        print("获取BFbeta信息失败")
        sys.exit(1)
    
    # 按beta值排序以便更好的显示
    bfbeta_data.sort(key=lambda x: x[1])
    
    # 计算边际似然值
    marginal_likelihood, contributions = calculate_marginal_likelihood(bfbeta_data, beta_weight_map)
    
    # 输出结果
    print(f"\n最终边际似然值: {marginal_likelihood:.6f}")
    
    with open(output_file, 'w') as f:
        f.write(f"Marginal Likelihood: {marginal_likelihood:.6f}\n\n")
        f.write("Detailed contributions:\n")
        f.write("Filename\t\t\tbeta\t\tweight\t\tElnfX\t\tcontribution\n")
        f.write("-" * 90 + "\n")
        for filename, beta, weight, elnfx, contribution in contributions:
            short_filename = os.path.basename(filename)
            f.write(f"{short_filename:20} {beta:10.6f} {weight:10.6f} {elnfx:15.2f} {contribution:15.2f}\n")
    
    print(f"详细结果已保存到: {output_file}")

if __name__ == "__main__":
    main()
