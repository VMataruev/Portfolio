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





