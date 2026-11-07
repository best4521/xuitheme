# xuitheme — قالب صفحه‌ی ساب 3x-ui (Nexino VPN)

صفحه‌ی اشتراک 3x-ui را با قالب سفارشی Nexino VPN عوض می‌کند (تم سرمه‌ای/آبی، QR، حجم، انقضا، کانفیگ‌ها، دکمه‌های Android/iOS).
اپ‌های VPN مثل قبل ساب معمولی را می‌گیرند و لینک کاربرها تغییر نمی‌کند.

## نصب / آپدیت

```bash
bash <(curl -Ls https://raw.githubusercontent.com/best4521/xuitheme/main/install.sh)
```

اسکریپت پورت ساب، دامنه و سرتیفیکیت را خودش از تنظیمات 3x-ui می‌خواند، nginx را روی همان پورت (مثلاً 2096) می‌گذارد و ساب x-ui را به `127.0.0.1:2097` منتقل می‌کند. قبل از تغییر از دیتابیس بکاپ می‌گیرد (`/root/backups`).

تنظیمات اختیاری:

```bash
PORT=2096 INTERNAL_PORT=2097 LOGO_URL=https://example.com/logo.png bash <(curl -Ls https://raw.githubusercontent.com/best4521/xuitheme/main/install.sh)
```

## حذف

```bash
bash <(curl -Ls https://raw.githubusercontent.com/best4521/xuitheme/main/install.sh) uninstall
```

## نکته
بعد از نصب، پورت و سرتیفیکیت ساب را از پنل 3x-ui تغییر ندهید.
