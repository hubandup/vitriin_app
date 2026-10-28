// Génère le visuel de test (JPEG 1080x1080) au moment du build Vercel.
// Instagram exige un JPEG accessible publiquement : il sera servi sur /promo-test.jpg.
import sharp from "sharp";
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080">
<defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="#e5087e"/><stop offset="1" stop-color="#951b81"/></linearGradient></defs>
<rect width="1080" height="1080" fill="url(#g)"/>
<circle cx="540" cy="470" r="260" fill="#f5ecd3" fill-opacity="0.14"/>
<text x="540" y="540" text-anchor="middle" font-family="DejaVu Sans, Liberation Sans, Arial, sans-serif" font-weight="bold" font-size="220" fill="#f5ecd3">-30%</text>
<text x="540" y="700" text-anchor="middle" font-family="DejaVu Sans, Liberation Sans, Arial, sans-serif" font-weight="bold" font-size="64" fill="#ffffff">Le Salon du Vélo</text>
<text x="540" y="790" text-anchor="middle" font-family="DejaVu Sans, Liberation Sans, Arial, sans-serif" font-size="40" fill="#f5ecd3">Publication de test Vitriin</text>
</svg>`;
await sharp(Buffer.from(svg)).jpeg({ quality: 88 }).toFile("public/promo-test.jpg");
console.log("promo-test.jpg généré");
