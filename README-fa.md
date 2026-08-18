[فارسی](README-fa.md) | [English](README.md)

راهنمای سریع: [راهنمای فارسی کلاینت](CLIENT-GUIDE.fa.md) | [English client guide](CLIENT-GUIDE.en.md)

# Aether OpenWrt Client

**نسخه کلاینت: v0.4.2**

اینتگریشن OpenWrt برای [Aether](https://github.com/CluvexStudio/Aether) — یک کلاینت دور زدن سانسور.

**Aether توسط [CluvexStudio](https://github.com/CluvexStudio) توسعه داده می‌شود. این ریپو یک نصب‌کننده OpenWrt و رابط وب LuCI فراهم می‌کند.**

## پیش‌نیازها

- **OpenWrt 24.10 یا جدیدتر** (musl libc؛ apk روی 25.12+، opkg روی 24.10 و قدیمی‌تر)
- تست شده روی OpenWrt 25.12.5 (x86_64)
- ~10 MB فضای دیسک آزاد
- معماری‌ها: x86_64، arm64 (aarch64)، armv7

## نصب (یک خط)

```sh
wget -qO /tmp/aether-install.sh https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main/install.sh && chmod +x /tmp/aether-install.sh && /tmp/aether-install.sh --start
```

در حین نصب از شما پرسیده می‌شود:

- **نسخه هسته Aether**: حداکثر پنج ریلیز پایدار از v1.5.0 به بعد نمایش داده
  می‌شود. با Enter نسخه پیش‌فرض v1.6.0 انتخاب می‌شود؛ می‌توانید یک گزینه یا
  نسخه معتبر v1.5.0 به بعد را وارد کنید.
- **curl نصب شود؟** به صورت پیش‌فرض **بله**. curl برای تست اتصال در LuCI و
  watchdog بازیابی تونل لازم است. با `--no-curl` از آن صرف‌نظر کنید؛ تونل کار
  می‌کند اما watchdog فعال نمی‌شود.

## این اسکریپت چه کاری انجام می‌دهد

1. معماری روتر شما را به صورت خودکار تشخیص می‌دهد (x86_64، arm64، armv7)
2. آخرین فایل باینری رسمی Aether را از [ریلیزهای CluvexStudio/Aether](https://github.com/CluvexStudio/Aether/releases) دانلود می‌کند
3. سرویس Aether (procd)، ابزار CLI، و رابط وب LuCI را نصب می‌کند
4. فایل‌های پشتیبانی (اسکریپت init، اپ LuCI، CLI، کانفیگ) را از GitHub دانلود می‌کند
5. checksum نوع SHA-256 فایل Aether دانلودشده را بررسی می‌کند

## قابلیت‌ها

- **CLI**: `aether-ctl start|stop|restart|status|show|log|test <host>` و `aether-ctl change-version <vX.Y.Z>`
- **LuCI**: Services -> Aether
  - جدول وضعیت (وضعیت، نسخه، endpoint، transport، آدرس SOCKS5)
  - دکمه‌های Start / Stop / Restart
  - دکمه‌های تست اتصال با زمان‌بندی دقیق میلی‌ثانیه
  - لاگ‌های زنده بلادرنگ (به‌روزرسانی خودکار، توقف/ادامه، اسکرول خودکار)
  - پیکربندی کامل (پروتکل، حالت اسکن، obfuscation، HTTP/2 و غیره)
- **سرویس**: ادغام procd، شروع خودکار هنگام بوت
- **watchdog بازیابی**: مسیر واقعی SOCKS5 را بررسی می‌کند و در صورت گیر کردن
  هسته، پس از چند خطای متوالی آن را بازیابی می‌کند
- **Zero Trust**: اتصال headless به سازمان با Access service token
- **معماری**: x86_64، arm64، armv7 (باینری‌های استاتیک musl)

## گزینه‌های نصب

```sh
/tmp/aether-install.sh                 # فقط نصب
/tmp/aether-install.sh --start         # نصب و شروع فوری
/tmp/aether-install.sh --force-config  # بازنویسی کانفیگ موجود
/tmp/aether-install.sh --no-curl       # رد شدن از پرامپت نصب curl
/tmp/aether-install.sh --version v1.5.0 --start
/tmp/aether-install.sh --non-interactive --start  # نسخه v1.6.0 بدون پرامپت
```

## حذف نصب

```sh
wget -qO /tmp/aether-uninstall.sh https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main/uninstall.sh
chmod +x /tmp/aether-uninstall.sh
/tmp/aether-uninstall.sh           # حذف فایل‌های برنامه؛ حفظ کانفیگ و هویت‌ها
/tmp/aether-uninstall.sh --purge   # حذف کانفیگ و داده‌های هویت نیز
```

## دستورات CLI

```sh
aether-ctl start
aether-ctl stop
aether-ctl restart
aether-ctl status
aether-ctl show
aether-ctl log              # نمایش لاگ‌های اخیر
aether-ctl log 100          # نمایش 100 خط آخر
aether-ctl test google.com  # تست اتصال از طریق تونل (نیاز به curl)
aether-ctl version
aether-ctl update
aether-ctl change-version v1.5.0 --start
aether-ctl update --version v1.5.0 --start
```

## به‌روزرسانی

دستور `aether-ctl update` آخرین `update.sh` این ریپو را دانلود و نصب‌کننده را
دوباره اجرا می‌کند. کانفیگ `/etc/config/aether` و هویت‌های معتبر `/etc/aether`
حفظ می‌شوند، مگر این‌که `--force-config` داده شود. فایل هسته همیشه با SHA-256
ریلیز رسمی بررسی می‌شود. کلاینت از هسته v1.5.0 و جدیدتر پشتیبانی می‌کند و
پیش‌فرض آن v1.6.0 است. پیش از شروع سرویس و پیش از رندر رابط LuCI، نسخه هسته
تشخیص داده می‌شود. در v1.5، گزینه‌های مخصوص v1.6 شامل HTTP CONNECT proxy،
MASQUE startup deadline و کنترل سطح لاگ نمایش داده نشده و به هسته ارسال
نمی‌شوند. نسخه‌های v1.6 و جدیدتر تا زمانی که پروفایل اختصاصی نداشته باشند،
رفتار v1.6 را دارند.

## رابط وب LuCI

پس از نصب، رابط وب روتر خود را باز کنید -> **Services -> Aether**

![رابط وب LuCI](screenshots/luci.png)

قابلیت‌ها:
- جدول وضعیت (وضعیت، نسخه، endpoint، transport)
- دکمه‌های Start / Stop / Restart
- دکمه‌های تست اتصال (google.com، youtube.com، github.com، telegram.org) با زمان دقیق ms
- لاگ‌های زنده بلادرنگ (به‌روزرسانی خودکار هر 2 ثانیه، بدون نیاز به رفرش دستی)
- توقف/ادامه استریم لاگ
- تاگل اسکرول خودکار
- دکمه پاک کردن لاگ‌ها
- پیکربندی کامل (پروتکل، حالت اسکن، obfuscation، HTTP/2 و غیره)

اگر بعد از به‌روزرسانی صفحه جدید LuCI یا فیلدهای جدید را نمی‌بینید، با
`Ctrl+F5` صفحه را hard refresh کنید یا از پنجره incognito/private و یا یک
مرورگر جدید استفاده کنید. cache جاوااسکریپت مرورگر ممکن است رابط قبلی را
نمایش دهد.

## به‌روزرسانی دستی (از کامپیوتر شما)

اگر ریپو را به صورت محلی کلون کرده‌اید و می‌خواهید فایل‌های به‌روزرسانی شده را بدون عبور از GitHub به روتر خود منتقل کنید:

```sh
# ایجاد آرشیو از دایرکتوری files
cd aether-openwrt-client
tar czf /tmp/aether-files.tar.gz files/

# انتقال به روتر (OpenWrt سرور scp ندارد، از wget در روتر استفاده کنید)
# در کامپیوتر شما، فایل را موقتاً سرو کنید:
python -m http.server 8888 --directory /tmp

# در روتر:
wget -O /tmp/aether-files.tar.gz http://<your-pc-ip>:8888/aether-files.tar.gz
tar xzf /tmp/aether-files.tar.gz -C /
/etc/init.d/aether restart
/etc/init.d/rpcd restart
```

یا فقط اسکریپت نصب را دوباره اجرا کنید (همیشه آخرین فایل‌ها را از GitHub دانلود می‌کند):

```sh
wget -qO /tmp/aether-install.sh https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main/install.sh && chmod +x /tmp/aether-install.sh && /tmp/aether-install.sh --start
```

## استفاده همزمان با Passwall 2 (پروکسی کل شبکه)

اگر می‌خواهید از **Passwall 2** (یا ابزارهای پروکسی شفاف مشابه) برای هدایت کل ترافیک شبکه از طریق پروکسی SOCKS5 نرم‌افزار Aether (پورت `127.0.0.1:1819`) استفاده کنید، **حتماً باید گزینه پروکسی لوکال‌هاست (Localhost Proxy / پروکسی خود روتر) را در سوییچ اصلی (Main Switch) پس‌وال غیرفعال (Disable) کنید.**

### چرا باید Localhost Proxy را غیرفعال کنیم؟ (زیر کاپوت چی می‌گذرد؟)
- **مشکل لوپ بی‌پایان (Routing Loop):** وقتی گزینه پروکسی لوکال‌هاست در Passwall فعال باشد، فایروال روتر تمام ترافیک خروجی که *از داخل خود روتر* تولید می‌شود (زنجیره `OUTPUT`) را شنود کرده و به سمت هسته پس‌وال هدایت می‌کند. از آنجایی که خود هسته Aether نیز به عنوان یک برنامه محلی روی روتر در حال اجراست، بسته‌های اسکن و هندشیک اولیه Aether (پکت‌های UDP 443 یا UDP 2408 که باید مستقیم به سرورهای کلودفلر برسند) توسط Passwall رهگیری شده و دوباره به سمت پروکسی Aether بازگردانده می‌شوند! این چرخه باعث یک لوپ بسته و باطل می‌شود و Aether هرگز موفق به برقراری ارتباط با اینترنت و بالا آوردن تونل نمی‌شود.
- **وقتی Localhost Proxy را غیرفعال می‌کنیم چه اتفاقی می‌افتد؟**
  1. **هسته Aether مستقیم وصل می‌شود:** ترافیک برنامه‌های داخلی روتر (شامل هسته Aether) از شنود Passwall عبور نکرده و مستقیماً از طریق رابط اینترنت WAN ارسال می‌شوند؛ در نتیجه Aether بدون اختلال آی‌پی‌ها را اسکن کرده و تونل را با کلودفلر برقرار می‌کند.
  2. **تمام دستگاه‌های متصل به شبکه (LAN) به صورت کامل پروکسی می‌شوند:** ترافیک کلاینت‌های متصل به شبکه محلی (موبایل‌ها، کامپیوترها، تلویزیون‌ها و...) همچنان از طریق زنجیره `PREROUTING` توسط Passwall دریافت شده و به صورت شفاف و کامل از داخل تونل امن Aether عبور داده می‌شود.

## نکات

- نیاز به OpenWrt 24.10+ با musl libc (apk روی 25.12+، opkg روی قدیمی‌تر)
- در نصب تازه، SOCKS5 روی `0.0.0.0:1819` است تا کلاینت‌های LAN استفاده کنند.
  SOCKS5 احراز هویت ندارد؛ firewall بگذارید یا برای استفاده فقط روی روتر،
  آدرس را به `127.0.0.1:1819` تغییر دهید.
- `curl` اختیاری است (در حین نصب پرسیده می‌شود، به صورت پیش‌فرض بله). برای
  تست اتصال LuCI و watchdog بازیابی تونل استفاده می‌شود.
- Secretهای Zero Trust در UCI فقط برای root ذخیره و در خروجی CLI و فرمان سرویس
  مخفی می‌شوند.
- برای تنظیمات، پروتکل‌ها، watchdog، Zero Trust و عیب‌یابی، [راهنمای فارسی
  کلاینت](CLIENT-GUIDE.fa.md) را ببینید.
- این پروژه وابسته به CluvexStudio نیست

## مجوز

MIT — فقط این نصب‌کننده و اپ LuCI. خود Aether تحت AGPL-3.0 است.

