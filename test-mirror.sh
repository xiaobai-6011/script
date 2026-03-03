#!/bin/bash
# 测试各镜像源延迟

echo "========================================"
echo "  镜像源延迟测试"
echo "========================================"

# 定义要测试的源
MIRRORS=(
    "mirrors.aliyun.com:阿里云"
    "mirrors.tuna.tsinghua.edu.cn:清华"
    "mirrors.cloud.tencent.com:腾讯云"
    "repo.huaweicloud.com:华为云"
    "mirrors.163.com:网易"
    "dl.google.com:Google"
    "github.com:GitHub"
)

for item in "${MIRRORS[@]}"; do
    host="${item%%:*}"
    name="${item##*:}"
    
    echo -n "$name ($host): "
    result=$(ping -c 1 -W 2 $host 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}')
    
    if [[ -n "$result" ]]; then
        echo -e "\033[32m${result} ms\033[0m"
    else
        echo -e "\033[31m超时\033[0m"
    fi
done

echo ""
echo "========================================"
echo "  测试完成"
echo "========================================"
