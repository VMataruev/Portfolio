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

# === СОЗДАНИЕ ВЕБ-СТРАНИЦ ===
echo "Создание веб-страниц..."

# Устанавливаем права
sudo chmod -R 755 $BASE_DIR

# === ГЛАВНАЯ СТРАНИЦА СРАВНЕНИЯ ===
cat <<EOF | sudo tee $BASE_DIR/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Лабораторная №7 - Обработка видео</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        header {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            display: flex;
            justify-content: center;
            gap: 30px;
            flex-wrap: wrap;
        }
        
        .a_box {
            position: relative;
        }
        
        .a_box a {
            text-decoration: none;
            color: #333;
            font-size: 18px;
            font-weight: 600;
            padding: 10px 20px;
            display: inline-block;
            transition: all 0.3s ease;
        }
        
        .a_box a:hover {
            color: #667eea;
        }
        
        .a_box_line {
            position: absolute;
            bottom: 0;
            left: 0;
            width: 0;
            height: 2px;
            background: linear-gradient(90deg, #667eea, #764ba2);
            transition: width 0.3s ease;
        }
        
        .a_box:hover .a_box_line {
            width: 100%;
        }
        
        h1 {
            text-align: center;
            color: white;
            margin-bottom: 30px;
            font-size: 2.5em;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(450px, 1fr));
            gap: 30px;
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            overflow: hidden;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-5px);
        }
        
        .card-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px;
            font-size: 1.2em;
            font-weight: bold;
            text-align: center;
        }
        
        .video-container {
            padding: 20px;
            background: #f5f5f5;
        }
        
        video {
            width: 100%;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        
        .info {
            padding: 15px;
            background: #f9f9f9;
            font-size: 14px;
            border-top: 1px solid #ddd;
        }
        
        .footer {
            text-align: center;
            color: white;
            margin-top: 40px;
            padding: 20px;
            background: rgba(0,0,0,0.3);
            border-radius: 10px;
        }
        
        .badge {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 12px;
            font-weight: bold;
            margin: 5px;
        }
        
        .ffmpeg {
            background: #ff6b6b;
            color: white;
        }
        
        .handbrake {
            background: #4ecdc4;
            color: white;
        }
    </style>
</head>
<body>
    <header>
        <div class="a_box">
            <a href="index.html">Главная</a>
            <div class="a_box_line"></div>
        </div>
        <div class="a_box">
            <a href="original.html">Исходные видео</a>
            <div class="a_box_line"></div>
        </div>
        <div class="a_box">
            <a href="processed.html">Обработанные</a>
            <div class="a_box_line"></div>
        </div>
        <div class="a_box">
            <a href="comparison.html">Сравнение</a>
            <div class="a_box_line"></div>
        </div>
    </header>
    
    <h1>🎬 Лабораторная работа №7<br>Обработка видео файлов</h1>
    
    <div class="container">
EOF

# Добавляем видео на главную страницу
for video in $OUT_DIR/*_ffmpeg.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video" _ffmpeg.mp4)
        hb_video="$OUT_DIR/${filename}_handbrake.mp4"
        
        if [ -f "$hb_video" ]; then
            cat <<EOF | sudo tee -a $BASE_DIR/index.html
        <div class="card">
            <div class="card-header">
                🎥 $filename
            </div>
            <div class="video-container">
                <video controls>
                    <source src="video/${filename}_ffmpeg.mp4" type="video/mp4">
                    Ваш браузер не поддерживает видео.
                </video>
            </div>
            <div class="info">
                <span class="badge ffmpeg">FFmpeg</span>
                <span class="badge handbrake">HandBrake</span>
                <p style="margin-top: 10px;">
                    <strong>Сравнение:</strong><br>
                    FFmpeg: быстрее, гибкая настройка<br>
                    HandBrake: лучшее качество сжатия, удобные пресеты
                </p>
            </div>
        </div>
EOF
        fi
    fi
done

cat <<EOF | sudo tee -a $BASE_DIR/index.html
    </div>
    
    <div class="footer">
        <p>© 2024 - Лабораторная работа №7 | Обработка видео с помощью FFmpeg и HandBrake</p>
        <p>Все видео конвертированы: AVI → MP4 (H.264 + AAC моно)</p>
        <p>Исходные файлы заархивированы в: /var/www/html/arhiv/video/</p>
    </div>
</body>
</html>
EOF

# === СТРАНИЦА С ИСХОДНЫМИ ВИДЕО ===
cat <<EOF | sudo tee $BASE_DIR/original.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Исходные видео (AVI)</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        header {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 30px;
            display: flex;
            justify-content: center;
            gap: 30px;
            flex-wrap: wrap;
        }
        .a_box a {
            text-decoration: none;
            color: #333;
            font-size: 18px;
            font-weight: 600;
            padding: 10px 20px;
        }
        h1 {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        .video-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            max-width: 1200px;
            margin: 0 auto;
        }
        .video-card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        video {
            width: 100%;
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <header>
        <div class="a_box"><a href="index.html">Главная</a></div>
        <div class="a_box"><a href="original.html">Исходные</a></div>
        <div class="a_box"><a href="processed.html">Обработанные</a></div>
        <div class="a_box"><a href="comparison.html">Сравнение</a></div>
    </header>
    <h1>📹 Исходные AVI файлы</h1>
    <div class="video-grid">
EOF

for video in $IN_DIR/*.avi; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat <<EOF | sudo tee -a $BASE_DIR/original.html
        <div class="video-card">
            <video controls>
                <source src="video_in/$filename" type="video/x-msvideo">
            </video>
            <p><strong>$filename</strong><br>Размер: ${size_mb} MB</p>
        </div>
EOF
    fi
done

cat <<EOF | sudo tee -a $BASE_DIR/original.html
    </div>
</body>
</html>
EOF

# === СТРАНИЦА С ОБРАБОТАННЫМИ ВИДЕО ===
cat <<EOF | sudo tee $BASE_DIR/processed.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Обработанные видео</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        header {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 30px;
            display: flex;
            justify-content: center;
            gap: 30px;
        }
        .a_box a {
            text-decoration: none;
            color: #333;
            font-size: 18px;
            font-weight: 600;
            padding: 10px 20px;
        }
        h1 { text-align: center; color: white; margin-bottom: 30px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 20px; max-width: 1200px; margin: 0 auto; }
        .card { background: white; border-radius: 10px; padding: 20px; }
        video { width: 100%; border-radius: 5px; }
        .ff { color: #ff6b6b; font-weight: bold; }
        .hb { color: #4ecdc4; font-weight: bold; }
    </style>
</head>
<body>
    <header>
        <div class="a_box"><a href="index.html">Главная</a></div>
        <div class="a_box"><a href="original.html">Исходные</a></div>
        <div class="a_box"><a href="processed.html">Обработанные</a></div>
        <div class="a_box"><a href="comparison.html">Сравнение</a></div>
    </header>
    <h1>🎞️ Обработанные видео (MP4)</h1>
    <div class="grid">
EOF

for video in $OUT_DIR/*.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        method=$(echo "$filename" | grep -q "ffmpeg" && echo "FFmpeg" || echo "HandBrake")
        class=$(echo "$filename" | grep -q "ffmpeg" && "ff" || "hb")
        cat <<EOF | sudo tee -a $BASE_DIR/processed.html
        <div class="card">
            <video controls>
                <source src="video/$filename" type="video/mp4">
            </video>
            <p><strong>$filename</strong><br>Метод: <span class="$class">$method</span><br>Размер: ${size_mb} MB</p>
        </div>
EOF
    fi
done

cat <<EOF | sudo tee -a $BASE_DIR/processed.html
    </div>
</body>
</html>
EOF

# === СТРАНИЦА СРАВНЕНИЯ ===
cat <<EOF | sudo tee $BASE_DIR/comparison.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Сравнение FFmpeg vs HandBrake</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        header {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 30px;
            display: flex;
            justify-content: center;
            gap: 30px;
        }
        .a_box a {
            text-decoration: none;
            color: #333;
            font-size: 18px;
            padding: 10px 20px;
        }
        h1 { text-align: center; color: white; margin-bottom: 30px; }
        .comparison-container { display: grid; grid-template-columns: 1fr 1fr; gap: 30px; max-width: 1200px; margin: 0 auto; }
        .method-card { background: white; border-radius: 15px; padding: 20px; }
        .method-card h2 { text-align: center; margin-bottom: 20px; }
        .ffmpeg-card h2 { color: #ff6b6b; }
        .handbrake-card h2 { color: #4ecdc4; }
        .stats { background: #f5f5f5; padding: 15px; border-radius: 10px; margin: 15px 0; }
        .advantage { background: #d4edda; padding: 10px; border-radius: 5px; margin: 10px 0; }
        .disadvantage { background: #f8d7da; padding: 10px; border-radius: 5px; margin: 10px 0; }
        video { width: 100%; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>
    <header>
        <div class="a_box"><a href="index.html">Главная</a></div>
        <div class="a_box"><a href="original.html">Исходные</a></div>
        <div class="a_box"><a href="processed.html">Обработанные</a></div>
        <div class="a_box"><a href="comparison.html">Сравнение</a></div>
    </header>
    <h1>📊 Сравнение методов конвертации</h1>
    <div class="comparison-container">
        <div class="method-card ffmpeg-card">
            <h2>🎬 FFmpeg</h2>
            <div class="stats">
                <p><strong>Преимущества:</strong></p>
                <div class="advantage">✓ Очень высокая скорость обработки</div>
                <div class="advantage">✓ Гибкие настройки кодека</div>
                <div class="advantage">✓ Меньше потребление ресурсов</div>
                <div class="advantage">✓ Отлично подходит для пакетной обработки</div>
                <p><strong>Недостатки:</strong></p>
                <div class="disadvantage">✗ Чуть хуже сжатие на низких битрейтах</div>
                <div class="disadvantage">✗ Сложнее освоить новичку</div>
            </div>
        </div>
        <div class="method-card handbrake-card">
            <h2>🎨 HandBrake</h2>
            <div class="stats">
                <p><strong>Преимущества:</strong></p>
                <div class="advantage">✓ Отличное качество сжатия</div>
                <div class="advantage">✓ Удобные готовые пресеты</div>
                <div class="advantage">✓ Лучшая работа с анимацией</div>
                <div class="advantage">✓ Есть графический интерфейс</div>
                <p><strong>Недостатки:</strong></p>
                <div class="disadvantage">✗ Медленнее FFmpeg в 1.5-2 раза</div>
                <div class="disadvantage">✗ Больше потребляет CPU</div>
            </div>
        </div>
    </div>
    <div style="max-width: 900px; margin: 30px auto; background: white; padding: 20px; border-radius: 15px;">
        <h3 style="text-align: center;">📝 Рекомендации</h3>
        <p><strong>Для быстрой обработки большого количества видео:</strong> используйте FFmpeg</p>
        <p><strong>Для максимального качества при минимальном размере:</strong> используйте HandBrake</p>
        <p><strong>Аудио:</strong> оба метода конвертируют звук в моно (AAC) для уменьшения размера</p>
        <p><strong>Формат:</strong> MP4 (H.264) - универсальный формат для веба</p>
        <hr>
        <p><strong>Лог обработки:</strong> <a href="process_video.log">process_video.log</a></p>
        <p><strong>Архив исходников:</strong> /var/www/html/arhiv/video/</p>
    </div>
</body>
</html>
EOF

# === НАСТРОЙКА ПРАВ ДОСТУПА ===
echo "Настройка прав доступа..."
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
echo "Результаты: /var/www/html/video/" | tee -a "$LOG_FILE"