#!/bin/bash
# 启用 pipefail 选项，确保管道中任意命令失败，整个管道都返回失败状态
set -o pipefail

# --- 配置区 ---
CODE_SERVER_ROOT="/usr/lib/code-server"
FONT_SOURCE="$HOME/JetBrainsMono-Regular.woff2"
FONT_TARGET="$CODE_SERVER_ROOT/src/browser/pages/JetBrainsMono-Regular.woff2"

# --- 字体文件检查和复制 ---
echo "检查字体文件..."

# 检查源字体文件是否存在
if [ ! -f "$FONT_SOURCE" ]; then
    echo "错误：源字体文件不存在：$FONT_SOURCE" >&2
    echo "请确保字体文件已放置在 $FONT_SOURCE" >&2
    exit 1
fi

# 检查目标字体文件是否存在
if [ -f "$FONT_TARGET" ]; then
    echo "字体文件已存在：$FONT_TARGET"
else
    echo "正在复制字体文件到：$FONT_TARGET"
    
    # 复制字体文件
    cp "$FONT_SOURCE" "$FONT_TARGET"
    if [ $? -eq 0 ]; then
        echo "字体文件复制成功！"
    else
        echo "错误：字体文件复制失败" >&2
        exit 1
    fi
fi

# --- CSS注入部分（原有逻辑）---
echo "检查workbench.html文件..."

WORKBENCH_FILE=$(find "$CODE_SERVER_ROOT" -name "workbench.html" | head -n 1)

if [ -z "$WORKBENCH_FILE" ]; then
    echo "错误：在 $CODE_SERVER_ROOT 中找不到 workbench.html 文件。" >&2
    exit 1
fi

CSS_ID="custom-font-injection-jetbrains-mono"
CSS_CONTENT="<style id=\"$CSS_ID\">
    @font-face {
      font-family: 'JetBrains Mono';
      font-style: normal;
      font-weight: 400;
      font-display: swap;
      src: url('_static/src/browser/pages/JetBrainsMono-Regular.woff2') format('woff2');
    }
    .monaco-editor, .xterm .xterm-rows {
        font-family: 'JetBrains Mono', monospace !important;
    }
</style>"

if grep -q "id=\"$CSS_ID\"" "$WORKBENCH_FILE"; then
    echo "CSS 已注入，无需操作。"
else
    echo "正在向 $WORKBENCH_FILE 注入 CSS..."

    TEMP_FILE=$(mktemp)
    if [ $? -ne 0 ]; then
        echo "错误：创建临时文件失败" >&2
        exit 1
    fi

    # 将注入操作和结果检查放在一起
    {
        awk -v css="$CSS_CONTENT" '/<\/head>/ {print css} 1' "$WORKBENCH_FILE" > "$TEMP_FILE" && \
        cat "$TEMP_FILE" | tee "$WORKBENCH_FILE" > /dev/null
    }

    # 检查管道命令的最终结果
    if [ $? -eq 0 ]; then
        echo "CSS 注入成功！"
    else
        echo "错误：CSS 注入失败。" >&2
        rm "$TEMP_FILE"
        exit 1
    fi

    rm "$TEMP_FILE"
fi

echo "字体配置完成！"