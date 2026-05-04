#!/bin/bash

# === ПЕРЕМЕННЫЕ ===
SRC_DIR="/var/www/portfolio.net/imgs_1"
IN_DIR="/var/www/portfolio.net/foto_in"
OUT_DIR="/var/www/portfolio.net/foto_www"
ARCH_DIR="/var/www/portfolio.net/arhiv/foto"
BASE_DIR="/var/www/portfolio.net"

# === СОЗДАНИЕ КАТАЛОГОВ ===
echo "Создание каталогов..."
sudo mkdir -p $IN_DIR
sudo mkdir -p $OUT_DIR
sudo mkdir -p $ARCH_DIR

# === УСТАНОВКА ПРОГРАММ ===
echo "Установка ImageMagick и архиваторов..."
sudo apt update
sudo apt install -y imagemagick zip bzip2

# === КОПИРОВАНИЕ JPG ===
echo "Копирование файлов..."
sudo cp $SRC_DIR/*.jpg $IN_DIR

# === ОБРАБОТКА ИЗОБРАЖЕНИЙ ===
echo "Обработка изображений..."

for img in $IN_DIR/*.jpg; do
    filename=$(basename "$img")
    
    # пример обработки: уменьшение + watermark
    convert "$img" -resize 800x600 -gravity South \
    -pointsize 20 -annotate +0+10 "Processed" \
    "$OUT_DIR/$filename"
done

# === АРХИВАЦИЯ ===
echo "Архивация..."

# zip
zip -j $ARCH_DIR/images.zip $IN_DIR/*.jpg

# === СОЗДАНИЕ HTML СТРАНИЦ ===
echo "Создание веб-страниц..."

# исходные
cat <<EOF | sudo tee $BASE_DIR/original.html
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Портфолио - Исходные изображения</title>
    <link rel="stylesheet" href="./style.css">
    <link rel="stylesheet" href="./main.css">
</head>
<body>
    <div class="hero-bg">
        <div class="stars"></div>
    </div>

    <header>
        <div class="a_box">
            <a href="../index.html">Обо мне</a>
            <div class="a_box_line"></div>
        </div>
        <div class="a_box">
            <a href="../projects/projects.html">Проекты</a>
            <div class="a_box_line"></div>
        </div>
        <div class="a_box">
            <a href="">Контакты</a>
            <div class="a_box_line"></div>
        </div>
    </header>
</body>
<script src="./stars.js"></script>
</html>

for img in $IN_DIR/*.jpg; do
    file=$(basename "$img")
    echo "<img src='foto_in/$file' width='200'>" | sudo tee -a $BASE_DIR/original.html
done

echo "</body></html>" | sudo tee -a $BASE_DIR/original.html

# обработанные
cat <<EOF | sudo tee $BASE_DIR/processed.html
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Портфолио - Обработанные изображения</title>
    <link rel="stylesheet" href="./style.css">
    <link rel="stylesheet" href="./main.css">
</head>
<body>
    <div class="hero-bg">
        <div class="stars"></div>
    </div>

    <header>
        <div class="a_box">
            <a href="../index.html">Обо мне</a>
            <div class="a_box_line"></div>
        </div>
        <div class="a_box">
            <a href="../projects/projects.html">Проекты</a>
            <div class="a_box_line"></div>
        </div>
        <div class="a_box">
            <a href="">Контакты</a>
            <div class="a_box_line"></div>
        </div>
    </header>
</body>
<script src="./stars.js"></script>
</html>

for img in $OUT_DIR/*.jpg; do
    file=$(basename "$img")
    echo "<img src='foto_www/$file' width='200'>" | sudo tee -a $BASE_DIR/processed.html
done

echo "</body></html>" | sudo tee -a $BASE_DIR/processed.html

echo "Готово!"