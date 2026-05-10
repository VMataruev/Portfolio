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

# === СОЗДАНИЕ ПРОСТЫХ ВЕБ-СТРАНИЦ ===
echo "Создание веб-страниц..."

# Устанавливаем права
sudo chown -R www-data:www-data $BASE_DIR
sudo chmod -R 755 $BASE_DIR

# === ПРОСТАЯ ГЛАВНАЯ СТРАНИЦА ===
cat <<EOF | sudo tee $BASE_DIR/index.html
<html>
<head>
    <meta charset="UTF-8">
    <title>Лабораторная работа №7 - Обработка видео</title>
</head>
<body>
    <h1>Лабораторная работа №7</h1>
    <h2>Обработка видео файлов</h2>
    
    <ul>
        <li><a href="original.html">Исходные видео (AVI)</a></li>
        <li><a href="processed.html">Обработанные видео (MP4)</a></li>
        <li><a href="comparison.html">Сравнение FFmpeg и HandBrake</a></li>
        <li><a href="process_video.log">Лог обработки</a></li>
    </ul>
    
    <hr>
    <p>Методы конвертации: FFmpeg и HandBrakeCLI</p>
    <p>Аудио: моно (AAC)</p>
    <p>Архив исходников: /var/www/html/arhiv/video/</p>
</body>
</html>
EOF

# === СТРАНИЦА С ИСХОДНЫМИ ВИДЕО ===
cat <<EOF | sudo tee $BASE_DIR/original.html
<html>
<head>
    <meta charset="UTF-8">
    <title>Исходные видео (AVI)</title>
</head>
<body>
    <h1>Исходные AVI файлы</h1>
    <p><a href="index.html">На главную</a></p>
    <hr>
EOF

for video in $IN_DIR/*.avi; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat <<EOF | sudo tee -a $BASE_DIR/original.html
    <div>
        <p><strong>$filename</strong> (${size_mb} MB)</p>
        <video width="400" controls>
            <source src="video_in/$filename" type="video/x-msvideo">
            Ваш браузер не поддерживает видео.
        </video>
        <hr>
    </div>
EOF
    fi
done

cat <<EOF | sudo tee -a $BASE_DIR/original.html
</body>
</html>
EOF

# === СТРАНИЦА С ОБРАБОТАННЫМИ ВИДЕО ===
cat <<EOF | sudo tee $BASE_DIR/processed.html
<html>
<head>
    <meta charset="UTF-8">
    <title>Обработанные видео (MP4)</title>
</head>
<body>
    <h1>Обработанные видео файлы</h1>
    <p><a href="index.html">На главную</a></p>
    <hr>
    <h2>Конвертация через FFmpeg</h2>
EOF

# Видео через FFmpeg
for video in $OUT_DIR/*_ffmpeg.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat <<EOF | sudo tee -a $BASE_DIR/processed.html
    <div>
        <p><strong>$filename</strong> (${size_mb} MB) - FFmpeg</p>
        <video width="400" controls>
            <source src="video/$filename" type="video/mp4">
            Ваш браузер не поддерживает видео.
        </video>
        <hr>
    </div>
EOF
    fi
done

cat <<EOF | sudo tee -a $BASE_DIR/processed.html
    <h2>Конвертация через HandBrake</h2>
EOF

# Видео через HandBrake
for video in $OUT_DIR/*_handbrake.mp4; do
    if [ -f "$video" ]; then
        filename=$(basename "$video")
        size=$(stat -c%s "$video")
        size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        cat <<EOF | sudo tee -a $BASE_DIR/processed.html
    <div>
        <p><strong>$filename</strong> (${size_mb} MB) - HandBrake</p>
        <video width="400" controls>
            <source src="video/$filename" type="video/mp4">
            Ваш браузер не поддерживает видео.
        </video>
        <hr>
    </div>
EOF
    fi
done

cat <<EOF | sudo tee -a $BASE_DIR/processed.html
</body>
</html>
EOF

# === СТРАНИЦА СРАВНЕНИЯ ===
cat <<EOF | sudo tee $BASE_DIR/comparison.html
<html>
<head>
    <meta charset="UTF-8">
    <title>Сравнение FFmpeg и HandBrake</title>
</head>
<body>
    <h1>Сравнение методов конвертации</h1>
    <p><a href="index.html">На главную</a></p>
    <hr>
    
    <h2>FFmpeg</h2>
    <ul>
        <li>✅ Высокая скорость обработки</li>
        <li>✅ Гибкие настройки</li>
        <li>✅ Меньше потребление ресурсов</li>
        <li>❌ Чуть хуже сжатие на низких битрейтах</li>
    </ul>
    
    <h2>HandBrake</h2>
    <ul>
        <li>✅ Отличное качество сжатия</li>
        <li>✅ Удобные готовые пресеты</li>
        <li>✅ Есть графический интерфейс</li>
        <li>❌ Медленнее FFmpeg в 1.5-2 раза</li>
    </ul>
    
    <hr>
    <h3>Рекомендации:</h3>
    <p><strong>Для быстрой обработки:</strong> используйте FFmpeg</p>
    <p><strong>Для максимального качества:</strong> используйте HandBrake</p>
    <p><strong>Аудио:</strong> оба метода конвертируют звук в моно (AAC)</p>
    <p><strong>Формат:</strong> MP4 (H.264) - универсальный формат для веба</p>
    
    <hr>
    <p><a href="process_video.log">Посмотреть полный лог обработки</a></p>
</body>
</html>
EOF

# === НАСТРОЙКА ПРАВ ДОСТУПА ===
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