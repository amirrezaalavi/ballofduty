# Ball of Duty

A small 3D shooter that runs in the browser. Five classes, four maps, five-minute matches.

[فارسی](#فارسی) · [Docs](docs/README.md) · [GitHub](https://github.com/amirrezaalavi/ballofduty)

## Run it

You need Linux or macOS, and Godot 4.7.2 with its export templates. The download links are in
[docs/development/SETUP.md](docs/development/SETUP.md).

```bash
git clone https://github.com/amirrezaalavi/ballofduty.git
cd ballofduty
./tools/dev.sh up
```

Open <http://127.0.0.1:8080>. Pick a class and a map, then press SOLO to play offline or JOIN MATCH
to play against bots on the local server. Click the canvas once, otherwise the browser keeps the
mouse.

The first start builds the web files, so give it a minute or two. Later starts are quick.

To stop everything:

```bash
./tools/dev.sh down
```

If port 8080 is taken, pick another one:

```bash
WEB_PORT=8081 ./tools/dev.sh up
```

The game server runs on port 9180 and the web port forwards to it, so the browser only needs one
address. The address you open is also the port the game connects to, so changing `WEB_PORT` is
enough.

### Put it online

Browsers only unlock some features over HTTPS, so a public server needs a domain with TLS. The
deployment notes show a reverse proxy setup: [docs/ci/DEPLOY.md](docs/ci/DEPLOY.md).

### Playing

WASD to move, mouse to look, left click to shoot, Space to jump, Shift to sprint, R to reload, Esc
for the menu.

---

## فارسی

یک بازی تیراندازی سه‌بعدی کوچک که داخل مرورگر اجرا می‌شود. پنج کلاس، چهار نقشه، هر مسابقه پنج دقیقه.

[مستندات](docs/README.md) · [گیت‌هاب](https://github.com/amirrezaalavi/ballofduty)

### اجرا

به لینوکس یا مک و Godot نسخه ۴.۷.۲ همراه با export templates نیاز دارید. لینک دانلود در
[مستندات نصب](docs/development/SETUP.md) هست.

```bash
git clone https://github.com/amirrezaalavi/ballofduty.git
cd ballofduty
./tools/dev.sh up
```

آدرس <http://127.0.0.1:8080> را باز کنید. یک کلاس و یک نقشه انتخاب کنید، بعد SOLO را برای بازی
آفلاین بزنید یا JOIN MATCH را برای بازی با بات‌ها روی سرور محلی. یک بار روی صفحه کلیک کنید تا
مرورگر کنترل ماوس را به بازی بدهد.

بار اول فایل‌های بازی ساخته می‌شوند و یکی دو دقیقه طول می‌کشد. دفعه‌های بعد سریع بالا می‌آید.

برای خاموش کردن:

```bash
./tools/dev.sh down
```

اگر پورت 8080 اشغال بود، پورت دیگری بدهید:

```bash
WEB_PORT=8081 ./tools/dev.sh up
```

سرور بازی روی پورت 9180 کار می‌کند و پورت وب به آن وصل می‌شود، پس مرورگر فقط یک آدرس لازم دارد.
همان آدرسی که باز می‌کنید پورت اتصال بازی هم هست، پس تغییر `WEB_PORT` کافی است.

### اجرا روی سرور اینترنتی

مرورگرها بعضی قابلیت‌ها را فقط روی HTTPS باز می‌کنند، پس سرور عمومی به دامنه و گواهی TLS نیاز
دارد. نمونه تنظیم reverse proxy در [مستندات استقرار](docs/ci/DEPLOY.md) هست.

### کنترل‌ها

WASD برای حرکت، ماوس برای چرخش دید، کلیک چپ برای شلیک، Space برای پرش، Shift برای دویدن، R برای
پر کردن خشاب، Esc برای منو.

---

## Docs

- [docs/README.md](docs/README.md) starts here.
- [docs/STATUS.md](docs/STATUS.md) is where the project is right now.
- [docs/development/SETUP.md](docs/development/SETUP.md) covers the engine install.
- [docs/ci/README.md](docs/ci/README.md) covers the pipeline and the browser checks.

## License

Code is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.
All current art and audio assets are CC0; the list is in [assets/CREDITS.md](assets/CREDITS.md).
