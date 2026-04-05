const circleBox = document.querySelector(".circle_box");

let mouseX = 0;
let mouseY = 0;

let currentX = 0;
let currentY = 0;

document.addEventListener("mousemove", (e) => {
    // нормализуем диапазон
    mouseX = (e.clientX / window.innerWidth - 0.5) * 1;
    mouseY = (e.clientY / window.innerHeight - 0.5) * 1;
});

function animate() {
    // плавность
    currentX += (mouseX * 40 - currentX) * 0.008;
    currentY += (mouseY * 40 - currentY) * 0.008;

    circleBox.style.transform = `translate(${currentX}px, ${currentY}px)`;

    requestAnimationFrame(animate);
}

animate();





const starsContainer = document.querySelector(".stars");

for (let i = 0; i < 120; i++) {
    const star = document.createElement("div");
    star.classList.add("star");

    const size = Math.random() * 3 + 1;
    const x = Math.random() * window.innerWidth;
    const y = Math.random() * window.innerHeight;
    const delay = Math.random() * 5;
    const duration = Math.random() * 3 + 2;

    star.style.width = `${size}px`;
    star.style.height = `${size}px`;
    star.style.left = `${x}px`;
    star.style.top = `${y}px`;
    star.style.animationDelay = `${delay}s`;
    star.style.animationDuration = `${duration}s`;

    starsContainer.appendChild(star);
}