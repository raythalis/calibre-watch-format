#!/bin/bash

# --- 配置 ---
SRC_BOOKS="/downloads/书籍"
SRC_MANGA="/downloads/漫画"
CHECK_FILE="/tmp/ebook_last_check.md5"
# 定义一个锁文件，用来标记主任务是否正在运行
LOCK_FILE="/tmp/ebook_task.lock"

# 1. 检查是否有锁：如果锁文件存在，说明上次主任务还没跑完
if [ -f "$LOCK_FILE" ]; then
    # 直接返回 1，飞牛 NAS 就不会启动新的主任务
    exit 1
fi

# 2. 计算当前目录指纹
current_state=$(ls -Rl "$SRC_BOOKS" "$SRC_MANGA" 2>/dev/null | md5sum)

# 3. 首次运行处理
if [ ! -f "$CHECK_FILE" ]; then
    echo "$current_state" > "$CHECK_FILE"
    exit 1
fi

# 4. 对比指纹
old_state=$(cat "$CHECK_FILE")
if [ "$current_state" != "$old_state" ]; then
    # 发现变化！
    # 在触发主任务前，先创建一个锁文件
    touch "$LOCK_FILE"
    # 更新指纹
    echo "$current_state" > "$CHECK_FILE"
    # 返回 0，触发主任务
    exit 0
else
    exit 1
fi