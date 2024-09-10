#!/bin/bash

# 检查参数数量
if [ "$#" -ne 2 ]; then
    echo "使用方法: $0 <输入列表文件> <输入/输出JSON文件>"
    exit 1
fi

INPUT_LIST="$1"
JSON_FILE="$2"

# 检查文件是否存在
if [ ! -f "$INPUT_LIST" ]; then
    echo "错误：输入列表文件 '$INPUT_LIST' 不存在"
    exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
    echo "错误：JSON文件 '$JSON_FILE' 不存在"
    exit 1
fi

# 创建临时文件
temp_domains_file=$(mktemp)
temp_suffixes_file=$(mktemp)
temp_keywords_file=$(mktemp)
temp_ip_cidr_file=$(mktemp)

# 提取现有的数据
jq -r '.rules[0].domain[]' "$JSON_FILE" | sort -u > "$temp_domains_file"
jq -r '.rules[0].domain_suffix[]' "$JSON_FILE" | sort -u > "$temp_suffixes_file"
jq -r '.rules[0].domain_keyword[]' "$JSON_FILE" 2>/dev/null | sort -u > "$temp_keywords_file"
jq -r '.rules[0].ip_cidr[]' "$JSON_FILE" 2>/dev/null | sort -u > "$temp_ip_cidr_file"

# 处理输入列表文件
while IFS= read -r line; do
    if [[ $line =~ ^DOMAIN, ]]; then
        domain=${line#DOMAIN,}
        grep -q "^$domain$" "$temp_domains_file" || echo "$domain" >> "$temp_domains_file"
    elif [[ $line =~ ^DOMAIN-SUFFIX, ]]; then
        suffix=${line#DOMAIN-SUFFIX,}
        grep -q "^$suffix$" "$temp_suffixes_file" || echo "$suffix" >> "$temp_suffixes_file"
    elif [[ $line =~ ^DOMAIN-KEYWORD, ]]; then
        keyword=${line#DOMAIN-KEYWORD,}
        grep -q "^$keyword$" "$temp_keywords_file" || echo "$keyword" >> "$temp_keywords_file"
    elif [[ $line =~ ^IP-CIDR, ]]; then
        ip_cidr=${line#IP-CIDR,}
        # 移除 no-resolve 选项（如果存在）
        ip_cidr=${ip_cidr%,no-resolve}
        grep -q "^$ip_cidr$" "$temp_ip_cidr_file" || echo "$ip_cidr" >> "$temp_ip_cidr_file"
    fi
done < "$INPUT_LIST"

# 排序并去重
sort -u -o "$temp_domains_file" "$temp_domains_file"
sort -u -o "$temp_suffixes_file" "$temp_suffixes_file"
sort -u -o "$temp_keywords_file" "$temp_keywords_file"
sort -u -o "$temp_ip_cidr_file" "$temp_ip_cidr_file"

# 更新 JSON 文件
jq --arg domains "$(cat "$temp_domains_file" | tr '\n' ',' | sed 's/,$//')" \
   --arg suffixes "$(cat "$temp_suffixes_file" | tr '\n' ',' | sed 's/,$//')" \
   --arg keywords "$(cat "$temp_keywords_file" | tr '\n' ',' | sed 's/,$//')" \
   --arg ip_cidrs "$(cat "$temp_ip_cidr_file" | tr '\n' ',' | sed 's/,$//')" \
   '.rules[0].domain = ($domains | split(",")) | 
    .rules[0].domain_suffix = ($suffixes | split(",")) | 
    .rules[0].domain_keyword = ($keywords | split(",")) | 
    .rules[0].ip_cidr = ($ip_cidrs | split(","))' \
   "$JSON_FILE" > "${JSON_FILE}.tmp"

mv "${JSON_FILE}.tmp" "$JSON_FILE"

# 清理临时文件
rm "$temp_domains_file" "$temp_suffixes_file" "$temp_keywords_file" "$temp_ip_cidr_file"

echo "$JSON_FILE 已更新。"
