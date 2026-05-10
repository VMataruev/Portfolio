#!/bin/bash

# === ПЕРЕМЕННЫЕ ===
SRC_DIR="/var/www/portfolio.net/video_source"          # внешний каталог с AVI файлами
IN_DIR="/var/www/portfolio.net/video_in"               # входные видео (копии исходников)
OUT_DIR="/var/www/portfolio.net/video"                 # обработанные видео (video_www)
ARCH_DIR="/var/www/portfolio.net/arhiv/video"          # архив исходников
BASE_DIR="/var/www/portfolio.net"                      # корень сайта
LOG_FILE="/var/www/portfolio.net/process_video.log"    # лог обработки

# === ОЧИСТКА ФАЙЛА ЛОГОВ ===
echo "=== ЛОГ ОБРАБОТКИ ВИДЕО ===" > "$LOG_FILE"
echo "Дата: $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# === СОЗДАНИЕ КАТАЛОГОВ ===
echo "Создание каталогов..."
sudo mkdir -p $IN_DIR
sudo mkdir -p $OUT_DIR
sudo mkdir -p $ARCH_DIR
sudo mkdir -p $BASE_DIR

# === УСТАНОВКА ПРОГРАММ ===
echo "Установка FFmpeg, HandBrakeCLI, архиваторов и веб-сервера..."
sudo apt update
sudo apt install -y ffmpeg handbrake-cli tar bzip2 apache2 wget

# Запуск веб-сервера
sudo systemctl start apache2
sudo systemctl enable apache2

# === КОПИРОВАНИЕ AVI ФАЙЛОВ ===
echo "Копирование AVI файлов из $SRC_DIR в $IN_DIR..."

# Проверяем существует ли исходный каталог
if [ ! -d "$SRC_DIR" ]; then
    echo "ВНИМАНИЕ: Каталог $SRC_DIR не найден!" | tee -a "$LOG_FILE"
    echo "Создаю тестовый каталог с демо-файлом..." | tee -a "$LOG_FILE"
    mkdir -p "$SRC_DIR"
    
    # Создаём тестовый AVI файл (цветные полосы, 5 секунд)
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=1 \
           -c:v libx264 -preset ultrafast "$SRC_DIR/test1.avi" -y 2>/dev/null
    ffmpeg -f lavfi -i testsrc=duration=7:size=320x240:rate=1 \
           -c:v libx264 -preset ultrafast "$SRC_DIR/test2.avi" -y 2>/dev/null
    echo "Создано 2 тестовых AVI файла" >> "$LOG_FILE"
fi

# Копируем все AVI файлы (до 20 штук)
count=0
for video in "$SRC_DIR"/*.avi; do
    if [ -f "$video" ] && [ $count -lt 20 ]; then
        sudo cp "$video" "$IN_DIR/"
        filename=$(basename "$video")
        echo "Скопирован: $filename" >> "$LOG_FILE"
        ((count++))
    fi
done
echo "Всего скопировано файлов: $count" | tee -a "$LOG_FILE"

# === ОБРАБОТКА ВИДЕО (КОНВЕРТАЦИЯ AVI -> MP4) ===
echo "Обработка видео (конвертация в MP4 с аудио моно)..."

for video in $IN_DIR/*.avi; do
    [ -f "$video" ] || continue
    
    filename=$(basename "$video" .avi)
    output_ff="$OUT_DIR/${filename}_ffmpeg.mp4"
    output_hb="$OUT_DIR/${filename}_handbrake.mp4"
    
    # размер ДО
    size_before=$(stat -c%s "$video")
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null)
    
    echo "================================" >> "$LOG_FILE"
    echo "Обработка файла: $filename.avi" >> "$LOG_FILE"
    echo "Длительность: ${duration} секунд" >> "$LOG_FILE"
    
    # === 1. Обработка через FFmpeg ===
    echo "Конвертация через FFmpeg..." >> "$LOG_FILE"
    start_time=$(date +%s)
    
    ffmpeg -i "$video" \
           -c:v libx264 -preset medium -crf 23 \
           -c:a aac -ac 1 -b:a 96k \
           -movflags +faststart \
           "$output_ff" -y 2>> "$LOG_FILE"
    
    end_time=$(date +%s)
    ff_time=$((end_time - start_time))
    
    # размер ПОСЛЕ (FFmpeg)
    size_after_ff=$(stat -c%s "$output_ff" 2>/dev/null || echo "0")
    
    # расчёт сжатия
    if [ $size_before -gt 0 ]; then
        diff_ff=$((size_before - size_after_ff))
        percent_ff=$(awk "BEGIN {printf \"%.2f\", ($diff_ff/$size_before)*100}")
    else
        percent_ff="0"
    fi
    
    echo "FFmpeg результат:" >> "$LOG_FILE"
    echo "  Исходный размер: $size_before байт" >> "$LOG_FILE"
    echo "  Новый размер: $size_after_ff байт" >> "$LOG_FILE"
    echo "  Сжатие: $percent_ff %" >> "$LOG_FILE"
    echo "  Время обработки: $ff_time сек" >> "$LOG_FILE"
    echo "  Сохранён: $output_ff" >> "$LOG_FILE"
    
    # === 2. Обработка через HandBrake ===
    echo "Конвертация через HandBrakeCLI..." >> "$LOG_FILE"
    start_time=$(date +%s)
    
    HandBrakeCLI -i "$video" -o "$output_hb" \
                 --preset="Fast 1080p30" \
                 --audio 1 --aencoder av_aac --mixdown mono \
                 --verbose=0 2>> "$LOG_FILE"
    
    end_time=$(date +%s)
    hb_time=$((end_time - start_time))
    
    # размер ПОСЛЕ (HandBrake)
    size_after_hb=$(stat -c%s "$output_hb" 2>/dev/null || echo "0")
    
    # расчёт сжатия
    if [ $size_before -gt 0 ]; then
        diff_hb=$((size_before - size_after_hb))
        percent_hb=$(awk "BEGIN {printf \"%.2f\", ($diff_hb/$size_before)*100}")
    else
        percent_hb="0"
    fi
    
    echo "HandBrake результат:" >> "$LOG_FILE"
    echo "  Исходный размер: $size_before байт" >> "$LOG_FILE"
    echo "  Новый размер: $size_after_hb байт" >> "$LOG_FILE"
    echo "  Сжатие: $percent_hb %" >> "$LOG_FILE"
    echo "  Время обработки: $hb_time сек" >> "$LOG_FILE"
    echo "  Сохранён: $output_hb" >> "$LOG_FILE"
    
    # Сравнение методов
    echo "Сравнение методов:" >> "$LOG_FILE"
    if [ $size_after_ff -lt $size_after_hb ]; then
        echo "  FFmpeg сжал сильнее на $((size_after_hb - size_after_ff)) байт" >> "$LOG_FILE"
    else
        echo "  HandBrake сжал сильнее на $((size_after_ff - size_after_hb)) байт" >> "$LOG_FILE"
    fi
    
    if [ $ff_time -lt $hb_time ]; then
        echo "  FFmpeg быстрее на $((hb_time - ff_time)) сек" >> "$LOG_FILE"
    else
        echo "  HandBrake быстрее на $((ff_time - hb_time)) сек" >> "$LOG_FILE"
    fi
    
    echo "-----------------------------" >> "$LOG_FILE"
done

# === АРХИВАЦИЯ ИСХОДНЫХ AVI ===
echo "Архивация исходных AVI файлов..."

ARCHIVE_NAME="video_original_$(date +%Y%m%d_%H%M%S).tar.bz2"
sudo tar -cjf "$ARCH_DIR/$ARCHIVE_NAME" -C "$IN_DIR" .

echo "Архив создан: $ARCH_DIR/$ARCHIVE_NAME" >> "$LOG_FILE"
echo "Размер архива: $(stat -c%s "$ARCH_DIR/$ARCHIVE_NAME" 2>/dev/null || echo "0") байт" >> "$LOG_FILE"

# === СОЗДАНИЕ ВЕБ-СТРАНИЦ В СТИЛЕ ПОРТФОЛИО ===
echo "Создание веб-страниц..."

# Устанавливаем права
sudo chown -R www-data:www-data $BASE_DIR
sudo chmod -R 755 $BASE_DIR

# === СТРАНИЦА С ИСХОДНЫМИ ВИДЕО (original.html) ===
cat <<'EOF' | sudo tee $BASE_DIR/original.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Портфолио - Исходные видео</title>
    <link rel="stylesheet" href="styles.css">
    <link rel="stylesheet" href="main.css">
    <style>
        .video-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 30px;
            padding: 40px;
            margin-top: 120px;
        }
        .video-card {
            background: rgba(255,255,255,0.05);
            border-radius: 15px;
            padding: 20px;
            transition: transform 0.3s ease;
            backdrop-filter: blur(10px);
        }
        .video-card:hover {
            transform: translateY(-5px);
            background: rgba(255,255,255,0.1);
        }
        .video-card video {
            width: 100%;
            border-radius: 10px;
            margin-bottom: 15px;
        }
        .video-card h3 {
            color: var(--brand-main);
            margin-bottom: 10px;
            font-size: 18px;
        }
        .video-card p {
            color: var(--text-gray);
            font-size: 14px;
        }
        .size-badge {
            display: inline-block;
            background: rgba(255,253,146,0.2);
            padding: 4px 10px;
            border-radius: 20px;
            font-size: 12px;
            margin-top: 10px;
        }
        .back-link {
            position: fixed;
            top: 100px;
            left: 40px;
            color: var(--brand-main);
            text-decoration: none;
            z-index: 100;
            background: rgba(0,0,0,0.5);
            padding: 10px 20px;
            border-radius: 25px;
            backdrop-filter: blur(5px);
            transition: 0.3s;
        }
        .back-link:hover {
            background: var(--brand-main);
            color: black;
        }
        h1 {
            text-align: center;
            margin-top: 100px;
            color: var(--brand-main);
        }
    </style>
</head>
<body>
    <div class="hero-bg">
        <div class="stars"></div>
    </div>

    <a href="./index.html" class="back-link">← На главную</a>

    <h1>📹 Исходные AVI видео</h1>
    
    <div class="video-grid">
EOF

# Добавляем видео на страницу
for video in $IN_DIR/*.avi; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat <<EOF | sudo tee -a $BASE_DIR/original.html
        <div class="video-card">
            <video controls>
                <source src="video_in/$filename" type="video/x-msvideo">
                Ваш браузер не поддерживает видео.
            </video>
            <h3>$filename</h3>
            <p>Размер: ${size_mb} MB</p>
            <div class="size-badge">Исходный файл AVI</div>
        </div>
EOF
    fi
done

cat <<'EOF' | sudo tee -a $BASE_DIR/original.html
    </div>

    <script src="main.js"></script>
    <script src="stars.js"></script>
</body>
</html>
EOF

# === СТРАНИЦА С ОБРАБОТАННЫМИ ВИДЕО (processed.html) ===
cat <<'EOF' | sudo tee $BASE_DIR/processed.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Портфолио - Обработанные видео</title>
    <link rel="stylesheet" href="styles.css">
    <link rel="stylesheet" href="main.css">
    <style>
        .method-section {
            margin: 120px 40px 40px 40px;
        }
        .method-title {
            color: var(--brand-main);
            font-size: 32px;
            margin-bottom: 30px;
            padding-left: 20px;
            border-left: 4px solid var(--brand-main);
        }
        .video-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 30px;
            margin-bottom: 60px;
        }
        .video-card {
            background: rgba(255,255,255,0.05);
            border-radius: 15px;
            padding: 20px;
            transition: transform 0.3s ease;
            backdrop-filter: blur(10px);
        }
        .video-card:hover {
            transform: translateY(-5px);
            background: rgba(255,255,255,0.1);
        }
        .video-card video {
            width: 100%;
            border-radius: 10px;
            margin-bottom: 15px;
        }
        .video-card h3 {
            color: var(--brand-main);
            margin-bottom: 10px;
            font-size: 16px;
            word-break: break-all;
        }
        .video-card p {
            color: var(--text-gray);
            font-size: 14px;
        }
        .method-badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 20px;
            font-size: 12px;
            margin-top: 10px;
        }
        .ffmpeg-badge {
            background: rgba(255,107,107,0.3);
            color: #ff6b6b;
        }
        .handbrake-badge {
            background: rgba(78,205,196,0.3);
            color: #4ecdc4;
        }
        .back-link {
            position: fixed;
            top: 100px;
            left: 40px;
            color: var(--brand-main);
            text-decoration: none;
            z-index: 100;
            background: rgba(0,0,0,0.5);
            padding: 10px 20px;
            border-radius: 25px;
            backdrop-filter: blur(5px);
            transition: 0.3s;
        }
        .back-link:hover {
            background: var(--brand-main);
            color: black;
        }
    </style>
</head>
<body>
    <div class="hero-bg">
        <div class="stars"></div>
    </div>

    <a href="./index.html" class="back-link">← На главную</a>

    <div class="method-section">
        <div class="method-title">🎬 FFmpeg</div>
        <div class="video-grid">
EOF

# Видео через FFmpeg
for video in $OUT_DIR/*_ffmpeg.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat <<EOF | sudo tee -a $BASE_DIR/processed.html
            <div class="video-card">
                <video controls>
                    <source src="video/$filename" type="video/mp4">
                    Ваш браузер не поддерживает видео.
                </video>
                <h3>$filename</h3>
                <p>Размер: ${size_mb} MB</p>
                <div class="method-badge ffmpeg-badge">FFmpeg | Аудио: моно</div>
            </div>
EOF
    fi
done

cat <<'EOF' | sudo tee -a $BASE_DIR/processed.html
        </div>
    </div>

    <div class="method-section">
        <div class="method-title">🎨 HandBrake</div>
        <div class="video-grid">
EOF

# Видео через HandBrake
for video in $OUT_DIR/*_handbrake.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat <<EOF | sudo tee -a $BASE_DIR/processed.html
            <div class="video-card">
                <video controls>
                    <source src="video/$filename" type="video/mp4">
                    Ваш браузер не поддерживает видео.
                </video>
                <h3>$filename</h3>
                <p>Размер: ${size_mb} MB</p>
                <div class="method-badge handbrake-badge">HandBrake | Аудио: моно</div>
            </div>
EOF
    fi
done

cat <<'EOF' | sudo tee -a $BASE_DIR/processed.html
        </div>
    </div>

    <script src="main.js"></script>
    <script src="stars.js"></script>
</body>
</html>
EOF

# === СТРАНИЦА СРАВНЕНИЯ (comparison.html) ===
cat <<'EOF' | sudo tee $BASE_DIR/comparison.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Портфолио - Сравнение методов</title>
    <link rel="stylesheet" href="styles.css">
    <link rel="stylesheet" href="main.css">
    <style>
        .comparison-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 40px;
            padding: 120px 40px 40px 40px;
            max-width: 1400px;
            margin: 0 auto;
        }
        .method-card {
            background: rgba(255,255,255,0.05);
            border-radius: 20px;
            padding: 30px;
            backdrop-filter: blur(10px);
            transition: transform 0.3s ease;
        }
        .method-card:hover {
            transform: translateY(-5px);
            background: rgba(255,255,255,0.08);
        }
        .method-card h2 {
            color: var(--brand-main);
            font-size: 28px;
            margin-bottom: 20px;
            text-align: center;
        }
        .method-card ul {
            list-style: none;
            padding: 0;
        }
        .method-card li {
            padding: 10px 0;
            color: var(--text-gray);
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .advantage {
            color: #4ecdc4;
        }
        .disadvantage {
            color: #ff6b6b;
        }
        .stats-box {
            background: rgba(0,0,0,0.3);
            border-radius: 15px;
            padding: 20px;
            margin-top: 20px;
        }
        .stats-box p {
            margin: 10px 0;
        }
        .back-link {
            position: fixed;
            top: 100px;
            left: 40px;
            color: var(--brand-main);
            text-decoration: none;
            z-index: 100;
            background: rgba(0,0,0,0.5);
            padding: 10px 20px;
            border-radius: 25px;
            backdrop-filter: blur(5px);
            transition: 0.3s;
        }
        .back-link:hover {
            background: var(--brand-main);
            color: black;
        }
        .recommendation {
            max-width: 900px;
            margin: 40px auto;
            background: rgba(255,253,146,0.1);
            border-radius: 20px;
            padding: 30px;
            text-align: center;
        }
        .recommendation h3 {
            color: var(--brand-main);
            margin-bottom: 20px;
        }
        .log-link {
            text-align: center;
            margin: 40px;
        }
        .log-link a {
            color: var(--brand-main);
            text-decoration: none;
            background: rgba(255,255,255,0.1);
            padding: 12px 24px;
            border-radius: 30px;
            transition: 0.3s;
        }
        .log-link a:hover {
            background: var(--brand-main);
            color: black;
        }
        h1 {
            text-align: center;
            margin-top: 100px;
            color: var(--brand-main);
        }
    </style>
</head>
<body>
    <div class="hero-bg">
        <div class="stars"></div>
    </div>

    <a href="./index.html" class="back-link">← На главную</a>

    <h1>📊 Сравнение методов конвертации</h1>

    <div class="comparison-container">
        <div class="method-card">
            <h2>⚡ FFmpeg</h2>
            <ul>
                <li class="advantage">✅ Высокая скорость обработки</li>
                <li class="advantage">✅ Гибкие настройки кодека</li>
                <li class="advantage">✅ Меньше потребление ресурсов</li>
                <li class="advantage">✅ Отлично для пакетной обработки</li>
                <li class="disadvantage">❌ Чуть хуже сжатие на низких битрейтах</li>
                <li class="disadvantage">❌ Сложнее для новичков</li>
            </ul>
            <div class="stats-box">
                <p>🎯 Лучшее применение:</p>
                <p>Быстрая обработка большого количества видео</p>
            </div>
        </div>

        <div class="method-card">
            <h2>🎨 HandBrake</h2>
            <ul>
                <li class="advantage">✅ Отличное качество сжатия</li>
                <li class="advantage">✅ Удобные готовые пресеты</li>
                <li class="advantage">✅ Лучшая работа с анимацией</li>
                <li class="advantage">✅ Есть графический интерфейс</li>
                <li class="disadvantage">❌ Медленнее FFmpeg в 1.5-2 раза</li>
                <li class="disadvantage">❌ Больше потребляет CPU</li>
            </ul>
            <div class="stats-box">
                <p>🎯 Лучшее применение:</p>
                <p>Максимальное качество при минимальном размере</p>
            </div>
        </div>
    </div>

    <div class="recommendation">
        <h3>💡 Рекомендации</h3>
        <p><strong>Для быстрой обработки:</strong> используйте FFmpeg</p>
        <p><strong>Для максимального качества:</strong> используйте HandBrake</p>
        <p><strong>Аудио:</strong> оба метода конвертируют звук в моно (AAC) для уменьшения размера</p>
        <p><strong>Формат:</strong> MP4 (H.264) - универсальный формат для веба</p>
    </div>

    <div class="log-link">
        <a href="process_video.log" target="_blank">📄 Посмотреть полный лог обработки</a>
    </div>

    <script src="main.js"></script>
    <script src="stars.js"></script>
</body>
</html>
EOF

# === ДОБАВЛЯЕМ ССЫЛКИ В ХЕДЕР НА ГЛАВНОЙ СТРАНИЦЕ (ЕСЛИ НУЖНО) ===
# Проверяем, есть ли уже ссылки на видео в хедере
if ! grep -q "video_in" "$BASE_DIR/index.html"; then
    # Добавляем ссылки в хедер, если их нет
    sudo sed -i '/<div class="a_box">/a\
            <div class="a_box">\
                <a href="./original.html">Исходные видео</a>\
                <div class="a_box_line"></div>\
            </div>\
\
            <div class="a_box">\
                <a href="./processed.html">Обработанные</a>\
                <div class="a_box_line"></div>\
            </div>\
\
            <div class="a_box">\
                <a href="./comparison.html">Сравнение</a>\
                <div class="a_box_line"></div>\
            </div>' "$BASE_DIR/index.html" 2>/dev/null || true
fi

sudo chown -R www-data:www-data $BASE_DIR
sudo chmod -R 755 $BASE_DIR

echo "================================" | tee -a "$LOG_FILE"
echo "ГОТОВО!" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Сайт доступен по адресу: http://$(hostname -I | awk '{print $1}')/" | tee -a "$LOG_FILE"
echo "Лог обработки: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Архив исходников: $ARCH_DIR" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "=== ИТОГОВЫЙ ОТЧЁТ ===" | tee -a "$LOG_FILE"
echo "Обработано файлов: $count" | tee -a "$LOG_FILE"
echo "Методы: FFmpeg и HandBrakeCLI" | tee -a "$LOG_FILE"
echo "Результаты: $OUT_DIR" | tee -a "$LOG_FILE"