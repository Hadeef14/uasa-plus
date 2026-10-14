import { readFileSync, writeFileSync, existsSync } from "node:fs";

let html = readFileSync("index.html", "utf8").replace(/\r\n?/g, "\n");

// 1. Remove duplicated full HTML copy after first </html>
const end = html.indexOf("</html>");
if (end !== -1) html = html.slice(0, end + 7) + "\n";

// 2. Inline curriculum.js if present
if (existsSync("curriculum.js")) {
  const js = readFileSync("curriculum.js", "utf8").replace(/<\/script>/gi, "<\\/script>");
  html = html.replace(
    /<script[^>]*src=["']curriculum\.js["'][^>]*><\/script>/i,
    `<script>\n${js}\n</script>`
  );
}

// 3. Fix broken lines.join("
// ")
html = html.replace(
  /lines\.join\(\s*"\s*\n\s*"\s*\)/g,
  () => 'lines.join("\\n")'
);

// 4. Fix missing silver medal
html = html.replace(
  /const m=\[\s*"🥇"\s*,\s*""\s*,\s*"🥉"\s*\]\s*;/g,
  'const m=["🥇","","🥉"];'
);

// 5. Add Form 1 / Form 2 daily mapping
html = html.replace(
  /\{\s*"Year 4"\s*:\s*4\s*,\s*"Year 5"\s*:\s*5\s*,\s*"Year 6"\s*:\s*6\s*\}/g,
  '{"Year 4":4,"Year 5":5,"Year 6":6,"Form 1":6,"Form 2":6}'
);

// 6. Add Form 1 / Form 2 profile dropdown
html = html.replace(
  /\[\s*"Year 4"\s*,\s*"Year 5"\s*,\s*"Year 6"\s*\]/g,
  '["Year 4","Year 5","Year 6","Form 1","Form 2"]'
);

// 7. Add Form 1 / Form 2 signup dropdown if missing
if (!html.includes("<option>Form 1</option>")) {
  html = html.replace(
    /(<select id="sy">)([\s\S]*?)(<\/select>)/,
    (_, open, inner, close) =>
      open + inner + "<option>Form 1</option><option>Form 2</option>" + close
  );
}

writeFileSync("index.html", html);
console.log("Fixed index.html");