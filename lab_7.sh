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

# === СОЗДАНИЕ КАТАЛОГОВ ===
echo "Creating directories..."
sudo mkdir -p $IN_DIR
sudo mkdir -p $OUT_DIR
sudo mkdir -p $ARCH_DIR

# === УСТАНОВКА ПРОГРАММ ===
echo "Installing programs..."
sudo apt update
sudo apt install -y ffmpeg handbrake-cli tar bzip2 apache2

sudo systemctl start apache2
sudo systemctl enable apache2

# === КОПИРОВАНИЕ AVI ФАЙЛОВ ===
echo "Copying AVI files..."

if [ ! -d "$SRC_DIR" ]; then
    mkdir -p "$SRC_DIR"
    echo "Please put AVI files in $SRC_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

for video in "$SRC_DIR"/*.avi; do
    if [ -f "$video" ]; then
        sudo cp "$video" "$IN_DIR/"
        echo "Copied: $(basename "$video")" >> "$LOG_FILE"
    fi
done

# === ОБРАБОТКА ВИДЕО ===
echo "Processing video..."

for video in $IN_DIR/*.avi; do
    [ -f "$video" ] || continue
    
    filename=$(basename "$video" .avi)
    
    echo "Processing: $filename" >> "$LOG_FILE"
    
    # FFmpeg
    ffmpeg -i "$video" \
           -c:v libx264 -preset medium -crf 23 \
           -c:a aac -ac 1 -b:a 96k \
           "$OUT_DIR/${filename}_ffmpeg.mp4" -y
    
    # HandBrake
    HandBrakeCLI -i "$video" -o "$OUT_DIR/${filename}_handbrake.mp4" \
                 --preset="Fast 1080p30" \
                 --audio 1 --aencoder av_aac --mixdown mono
    
    echo "Done: $filename" >> "$LOG_FILE"
done

# === АРХИВАЦИЯ ===
echo "Archiving..."

ARCHIVE_NAME="video_original_$(date +%Y%m%d_%H%M%S).tar.bz2"
sudo tar -cjf "$ARCH_DIR/$ARCHIVE_NAME" -C "$IN_DIR" .

# === СОЗДАНИЕ СТРАНИЦ ===

# original.html
cat > $BASE_DIR/original.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Исходные видео</title>
    <link rel="stylesheet" href="styles.css">
    <link rel="stylesheet" href="main.css">
</head>
<body>
    <div class="hero-bg"><div class="stars"></div></div>
    
    <header>
        <div class="a_box"><a href="./index.html">Обо мне</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./projects/projects.html">Проекты</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./contacts/contacts.html">Контакты</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./original.html">Оригиналы</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./processed.html">Обработанные</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./comparison.html">Сравнение</a><div class="a_box_line"></div></div>
    </header>

    <h1 style="text-align:center; margin-top:100px; color:var(--brand-main);">Исходные AVI</h1>
    <div style="display:grid; grid-template-columns:repeat(auto-fill,minmax(400px,1fr)); gap:30px; padding:40px; margin-top:120px;">
EOF

for video in $IN_DIR/*.avi; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat >> $BASE_DIR/original.html << EOF
        <div style="background:rgba(255,255,255,0.05); border-radius:15px; padding:20px;">
            <video controls style="width:100%; border-radius:10px;">
                <source src="video_in/$filename" type="video/x-msvideo">
            </video>
            <h3 style="color:var(--brand-main);">$filename</h3>
            <p style="color:var(--text-gray);">Size: ${size_mb} MB</p>
        </div>
EOF
    fi
done

cat >> $BASE_DIR/original.html << 'EOF'
    </div>
    <script src="main.js"></script>
    <script src="stars.js"></script>
</body>
</html>
EOF

# processed.html
cat > $BASE_DIR/processed.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Обработанные видео</title>
    <link rel="stylesheet" href="styles.css">
    <link rel="stylesheet" href="main.css">
    <style>
        .section { margin: 120px 40px 40px 40px; }
        .title { color: var(--brand-main); font-size: 28px; margin-bottom: 30px; border-left: 4px solid var(--brand-main); padding-left: 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 30px; margin-bottom: 60px; }
        .card { background: rgba(255,255,255,0.05); border-radius: 15px; padding: 20px; }
        .card video { width: 100%; border-radius: 10px; margin-bottom: 15px; }
        .card h3 { color: var(--brand-main); font-size: 14px; }
        .card p { color: var(--text-gray); font-size: 14px; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 20px; font-size: 12px; margin-top: 10px; }
        .ff { background: rgba(255,107,107,0.3); color: #ff6b6b; }
        .hb { background: rgba(78,205,196,0.3); color: #4ecdc4; }
    </style>
</head>
<body>
    <div class="hero-bg"><div class="stars"></div></div>
    
    <header>
        <div class="a_box"><a href="./index.html">Обо мне</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./projects/projects.html">Проекты</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./contacts/contacts.html">Контакты</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./original.html">Оригиналы</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./processed.html">Обработанные</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./comparison.html">Сравнение</a><div class="a_box_line"></div></div>
    </header>

    <div class="section">
        <div class="title">FFmpeg</div>
        <div class="grid">
EOF

for video in $OUT_DIR/*_ffmpeg.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat >> $BASE_DIR/processed.html << EOF
            <div class="card">
                <video controls><source src="video/$filename" type="video/mp4"></video>
                <h3>$filename</h3>
                <p>Size: ${size_mb} MB</p>
                <div class="badge ff">FFmpeg</div>
            </div>
EOF
    fi
done

cat >> $BASE_DIR/processed.html << 'EOF'
        </div>
    </div>

    <div class="section">
        <div class="title">HandBrake</div>
        <div class="grid">
EOF

for video in $OUT_DIR/*_handbrake.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat >> $BASE_DIR/processed.html << EOF
            <div class="card">
                <video controls><source src="video/$filename" type="video/mp4"></video>
                <h3>$filename</h3>
                <p>Size: ${size_mb} MB</p>
                <div class="badge hb">HandBrake</div>
            </div>
EOF
    fi
done

cat >> $BASE_DIR/processed.html << 'EOF'
        </div>
    </div>
    <script src="main.js"></script>
    <script src="stars.js"></script>
</body>
</html>
EOF

# comparison.html
cat > $BASE_DIR/comparison.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Сравнение</title>
    <link rel="stylesheet" href="styles.css">
    <link rel="stylesheet" href="main.css">
    <style>
        .container { display: grid; grid-template-columns: repeat(2, 1fr); gap: 40px; padding: 120px 40px 40px 40px; max-width: 1200px; margin: 0 auto; }
        .card { background: rgba(255,255,255,0.05); border-radius: 20px; padding: 30px; }
        .card h2 { color: var(--brand-main); text-align: center; margin-bottom: 20px; }
        .card ul { list-style: none; padding: 0; }
        .card li { padding: 10px 0; color: var(--text-gray); border-bottom: 1px solid rgba(255,255,255,0.1); }
        .log { text-align: center; margin: 40px; }
        .log a { color: var(--brand-main); background: rgba(255,255,255,0.1); padding: 12px 24px; border-radius: 30px; text-decoration: none; }
        h1 { text-align: center; margin-top: 100px; color: var(--brand-main); }
    </style>
</head>
<body>
    <div class="hero-bg"><div class="stars"></div></div>
    
    <header>
        <div class="a_box"><a href="./index.html">Обо мне</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./projects/projects.html">Проекты</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./contacts/contacts.html">Контакты</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./original.html">Оригиналы</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./processed.html">Обработанные</a><div class="a_box_line"></div></div>
        <div class="a_box"><a href="./comparison.html">Сравнение</a><div class="a_box_line"></div></div>
    </header>

    <h1>Сравнение FFmpeg и HandBrake</h1>

    <div class="container">
        <div class="card">
            <h2>FFmpeg</h2>
            <ul>
                <li>Высокая скорость</li>
                <li>Гибкие настройки</li>
                <li>Меньше ресурсов</li>
                <li>Хуже сжатие</li>
            </ul>
        </div>
        <div class="card">
            <h2>HandBrake</h2>
            <ul>
                <li>Лучшее качество</li>
                <li>Готовые пресеты</li>
                <li>Есть GUI</li>
                <li>Медленнее</li>
            </ul>
        </div>
    </div>

    <div class="log">
        <a href="process_video.log">Лог обработки</a>
    </div>

    <script src="main.js"></script>
    <script src="stars.js"></script>
</body>
</html>
EOF

sudo chown -R www-data:www-data $BASE_DIR
sudo chmod -R 755 $BASE_DIR

echo "Done!"
echo "Site: http://$(hostname -I | awk '{print $1}')/"