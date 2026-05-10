#!/bin/bash

# === ПЕРЕМЕННЫЕ ===
SRC_DIR="/var/www/portfolio.net/video_source"
IN_DIR="/var/www/portfolio.net/video_in"
OUT_DIR="/var/www/portfolio.net/video"
ARCH_DIR="/var/www/portfolio.net/arhiv/video"
BASE_DIR="/var/www/portfolio.net"
LOG_FILE="/var/www/portfolio.net/process_video.log"

# === ОЧИСТКА ФАЙЛА ЛОГОВ ===
echo "=== LOG VIDEO PROCESSING ===" > "$LOG_FILE"
echo "Date: $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# === CREATE DIRECTORIES ===
echo "Creating directories..."
sudo mkdir -p $IN_DIR
sudo mkdir -p $OUT_DIR
sudo mkdir -p $ARCH_DIR
sudo mkdir -p $BASE_DIR

# === INSTALL PROGRAMS ===
echo "Installing FFmpeg, HandBrakeCLI, archivers and web server..."
sudo apt update
sudo apt install -y ffmpeg handbrake-cli tar bzip2 apache2 wget

sudo systemctl start apache2
sudo systemctl enable apache2

# === COPY AVI FILES ===
echo "Copying AVI files from $SRC_DIR to $IN_DIR..."

if [ ! -d "$SRC_DIR" ]; then
    echo "WARNING: Directory $SRC_DIR not found!" | tee -a "$LOG_FILE"
    echo "Creating test directory with demo file..." | tee -a "$LOG_FILE"
    mkdir -p "$SRC_DIR"
    
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=1 \
           -c:v libx264 -preset ultrafast "$SRC_DIR/test1.avi" -y 2>/dev/null
    ffmpeg -f lavfi -i testsrc=duration=7:size=320x240:rate=1 \
           -c:v libx264 -preset ultrafast "$SRC_DIR/test2.avi" -y 2>/dev/null
    echo "Created 2 test AVI files" >> "$LOG_FILE"
fi

count=0
for video in "$SRC_DIR"/*.avi; do
    if [ -f "$video" ] && [ $count -lt 20 ]; then
        sudo cp "$video" "$IN_DIR/"
        filename=$(basename "$video")
        echo "Copied: $filename" >> "$LOG_FILE"
        ((count++))
    fi
done
echo "Total copied files: $count" | tee -a "$LOG_FILE"

# === VIDEO PROCESSING (AVI -> MP4) ===
echo "Processing video (converting to MP4 with mono audio)..."

for video in $IN_DIR/*.avi; do
    [ -f "$video" ] || continue
    
    filename=$(basename "$video" .avi)
    output_ff="$OUT_DIR/${filename}_ffmpeg.mp4"
    output_hb="$OUT_DIR/${filename}_handbrake.mp4"
    
    size_before=$(stat -c%s "$video")
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null)
    
    echo "================================" >> "$LOG_FILE"
    echo "Processing file: $filename.avi" >> "$LOG_FILE"
    echo "Duration: ${duration} seconds" >> "$LOG_FILE"
    
    # FFmpeg conversion
    echo "Converting via FFmpeg..." >> "$LOG_FILE"
    start_time=$(date +%s)
    
    ffmpeg -i "$video" \
           -c:v libx264 -preset medium -crf 23 \
           -c:a aac -ac 1 -b:a 96k \
           -movflags +faststart \
           "$output_ff" -y 2>> "$LOG_FILE"
    
    end_time=$(date +%s)
    ff_time=$((end_time - start_time))
    
    size_after_ff=$(stat -c%s "$output_ff" 2>/dev/null || echo "0")
    
    if [ $size_before -gt 0 ]; then
        diff_ff=$((size_before - size_after_ff))
        percent_ff=$(awk "BEGIN {printf \"%.2f\", ($diff_ff/$size_before)*100}")
    else
        percent_ff="0"
    fi
    
    echo "FFmpeg result:" >> "$LOG_FILE"
    echo "  Original size: $size_before bytes" >> "$LOG_FILE"
    echo "  New size: $size_after_ff bytes" >> "$LOG_FILE"
    echo "  Compression: $percent_ff %" >> "$LOG_FILE"
    echo 