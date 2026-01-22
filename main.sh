#!/bin/bash

# --- 基础配置 ---
CONTAINER_NAME="calibre-desktop"
LIB_BOOKS="/library/书籍"    
LIB_MANGA="/library/漫画"    
SRC_BOOKS="/downloads/书籍"
SRC_MANGA="/downloads/漫画"
TEMP_DIR="/temp_process"    
LOG_FILE="/vol1/1000/docker/calibre/auto_add.log"

echo "------------------------------------------------" >> $LOG_FILE
echo "$(date) - 启动【全量暴力入库模式】..." >> $LOG_FILE
echo "提示：此模式不检查查重，将直接转换并覆盖入库。" >> $LOG_FILE

# 初始化环境
docker exec -i $CONTAINER_NAME mkdir -p "$TEMP_DIR" "$LIB_BOOKS" "$LIB_MANGA"
# 确保起始状态临时文件夹是干净的
docker exec -i $CONTAINER_NAME sh -c "rm -rf $TEMP_DIR/*"

process_folder() {
    local src="$1"
    local target_lib="$2"
    local type_label="$3"

    echo ">>> 正在扫描 $type_label 目录: $src" >> $LOG_FILE

    # 将文件列表存入临时文件，避免循环被 docker exec 中断
    local queue_file="/tmp/queue_${type_label}.txt"
    docker exec -i $CONTAINER_NAME sh -c "find '$src' -type f \( -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.epub' -o -iname '*.cbz' \)" > "$queue_file"

    # 统计总数
    local total_count=$(wc -l < "$queue_file")
    echo "发现 $total_count 本 $type_label，准备开始处理..." >> $LOG_FILE

    local current=0
    # 使用文件描述符 3 读取
    while IFS= read -u 3 -r book_path; do
        [ -z "$book_path" ] && continue
        ((current++))
        
        filename=$(basename "$book_path")
        name_no_ext="${filename%.*}"
        extension="${filename##*.}"

        echo "[$current/$total_count] 正在处理: $filename" >> $LOG_FILE

        # 1. 转换/准备阶段
        if [[ "$extension" =~ ^(mobi|azw3|MOBI|AZW3)$ ]]; then
            echo "   - 格式为 $extension，正在执行 EPUB 转换..." >> $LOG_FILE
            local conv_opts=""
            [[ "$type_label" == "漫画" ]] && conv_opts="--no-default-epub-cover"
            
            # 执行转换
            docker exec -i $CONTAINER_NAME ebook-convert "$book_path" "$TEMP_DIR/${name_no_ext}.epub" $conv_opts </dev/null >> $LOG_FILE 2>&1
            
            if [ $? -eq 0 ]; then
                echo "   - 转换成功" >> $LOG_FILE
                local add_path="$TEMP_DIR/${name_no_ext}.epub"
            else
                echo "   [ERROR] $filename 转换失败，跳过入库" >> $LOG_FILE
                continue
            fi
        else
            echo "   - 格式为 $extension，无需转换，直接准备入库..." >> $LOG_FILE
            docker exec -i $CONTAINER_NAME cp "$book_path" "$TEMP_DIR/"
            local add_path="$TEMP_DIR/$filename"
        fi

        # 2. 入库阶段
        echo "   - 正在将文件推送到 Calibre 数据库 ($target_lib)..." >> $LOG_FILE
        docker exec -i $CONTAINER_NAME calibredb add "$add_path" --with-library "$target_lib" --automerge overwrite >> $LOG_FILE 2>&1
        
        if [ $? -eq 0 ]; then
            echo "   [OK] $filename 录入/覆盖成功" >> $LOG_FILE
        else
            echo "   [FAILED] $filename 录入数据库失败" >> $LOG_FILE
        fi

        # 3. 清理临时区
        docker exec -i $CONTAINER_NAME sh -c "rm -rf $TEMP_DIR/*"
        echo "-----------------------------------" >> $LOG_FILE

    done 3< "$queue_file"
    
    rm -f "$queue_file"
}

# 执行任务
process_folder "$SRC_BOOKS" "$LIB_BOOKS" "书籍"
process_folder "$SRC_MANGA" "$LIB_MANGA" "漫画"

echo "$(date) - 所有任务执行完毕。" >> $LOG_FILE
rm -f /tmp/ebook_task.lock