# راهنمای کلاینت Aether برای OpenWrt

این کلاینت هسته Aether را با OpenWrt یکپارچه می‌کند. باینری Aether، سرویس
procd، دستور `aether-ctl` و صفحه LuCI در مسیر **Services -> Aether** نصب می‌شوند.

## چه کاری انجام می‌دهد؟

Aether یک پراکسی محلی SOCKS5 ایجاد می‌کند و ترافیک را از تونل عبور می‌دهد.
این یکپارچه‌سازی OpenWrt:

- هسته را با procd اجرا و مدیریت می‌کند؛
- هویت‌ها را در `/etc/aether` نگه می‌دارد؛
- start، stop، restart، status، لاگ و تست اتصال را فراهم می‌کند؛
- صفحه تنظیمات LuCI دارد؛
- مسیر واقعی داده را بررسی می‌کند و در صورت گیر کردن هسته آن را بازیابی می‌کند.

آدرس پیش‌فرض پراکسی `0.0.0.0:1819` است. اگر پراکسی فقط باید روی خود روتر
قابل دسترسی باشد، آن را به `127.0.0.1:1819` تغییر دهید.

## پروتکل‌ها

- **MASQUE**: حالت مدرن با HTTP/3 و QUIC. اگر UDP یا QUIC مسدود است، HTTP/2
  را فعال کنید. پروفایل پیشنهادی MASQUE، `firewall` است.
- **WireGuard**: در شبکه‌هایی که WireGuard مسدود نیست معمولاً سریع‌تر است.
  پروفایل‌های آن `balanced`، `aggressive`، `light` و `off` هستند.
- **WARP-in-WARP (gool)**: دو لایه WireGuard دارد و ممکن است در شبکه‌های سخت‌گیر
  بهتر کار کند، اما سربار بیشتری دارد. از `balanced` شروع کنید.

کلاینت endpointها را اسکن کرده و قبل از باز کردن SOCKS5، عبور واقعی داده را
بررسی می‌کند. گزینه **Quick Reconnect** ابتدا endpoint موفق قبلی را بررسی
می‌کند تا در صورت امکان از اسکن کامل جلوگیری شود.

## تنظیمات

### تنظیمات پایه و شبکه

- **Enable on Boot** فقط شروع خودکار بعد از ریبوت روتر را کنترل می‌کند و مانع
  استفاده از دکمه‌های Start و Stop یا دستورات CLI در زمان فعلی نمی‌شود.
- **Scan Mode**: حالت `turbo` سریع‌تر است؛ `balanced` انتخاب معمول است؛
  حالت‌های `thorough`، `stealth` و `ironclad` زمان بیشتری برای کشف یا اعتبارسنجی
  صرف می‌کنند.
- **IP Version**: اگر IPv6 روی روتر فعال و سالم نیست، IPv4 را انتخاب کنید.
- **Force Peer**: با وارد کردن `ip:port` اسکن را رد می‌کند.
- **HTTP/2 Mode** و **H2 Peer** فقط برای MASQUE هستند.
- **TLS Fragmentation** برای MASQUE روی HTTP/2 و در صورت مسدود بودن handshake است.
- **HTTP CONNECT Proxy** به‌صورت اختیاری همان تونل را برای برنامه‌های بدون SOCKS5
  فراهم می‌کند.
- **Upstream Proxy** (نیازمند هسته v1.7+) تونل را پشت یک پروکسی دیگر زنجیر
  می‌کند. مقدار آن می‌تواند `socks5://[user:pass@]host:port`، `http://host:port`
  یا فقط `host:port` (SOCKS5 در نظر گرفته می‌شود) باشد. پروکسی SOCKS5 بالادستی
  همه transportها را پشتیبانی می‌کند؛ پروکسی HTTP CONNECT به حالت HTTP/2 نیاز
  دارد. این مقدار مستقیماً از طریق پرچم `--upstream` به هسته داده می‌شود و در
  `aether-ctl show` مخفی (redact) نمایش داده می‌شود.
- **MASQUE Startup Deadline** برای اتصال و اولین اعتبارسنجی داده محدودیت زمانی
  می‌گذارد و مقدار پیش‌فرض آن ۳۰ ثانیه است.

### تنظیمات پایداری

- **Keepalive** برای WireGuard و gool استفاده می‌شود.
- **Reconnect Delay** فاصله تلاش مجدد هسته را تعیین می‌کند.
- **Validation Timeout** زمان انتظار اعتبارسنجی مسیر داده است.
- **Quick Reconnect** endpoint ذخیره‌شده را قبل از اسکن دوباره بررسی می‌کند.
- **Data-plane Watchdog** ترافیک SOCKS5 را دوره‌ای تست می‌کند و پس از چند خطای
  متوالی، هسته گیرکرده را متوقف می‌کند تا procd یک نمونه سالم اجرا کند. برای
  فعال شدن آن باید `curl` نصب باشد.

## Zero Trust

بخش **Zero Trust** در LuCI از اتصال headless به سازمان Cloudflare پشتیبانی می‌کند:

- نام Team؛
- Access Client ID؛
- Access Client Secret؛
- Existing Access Token برای استقرار headless؛
- حالت اختیاری Gateway سازمان.

Secret در `/etc/config/aether` ذخیره می‌شود، فایل فقط برای root قابل خواندن است
و مقدار آن در خروجی CLI و فهرست فرمان سرویس نمایش داده نمی‌شود. Gateway به صورت
پیش‌فرض خاموش است، چون فیلتر و لاگ سازمان باید انتخابی باشد.

ورود تعاملی با کد ایمیل را از ترمینال و با خود هسته Aether انجام دهید؛ سرویس boot
برای ورود تعاملی مناسب نیست.

## یکپارچگی Passwall2

اگر از Passwall 2 برای پروکسی شفاف کلاینت‌های LAN از داخل تونل Aether استفاده
می‌کنید، کلاینت می‌تواند تنظیمات لازم را مدیریت کند. از بخش **Passwall2
Integration** در صفحه LuCI (زیر *تنظیمات Advanced*) یا خط فرمان استفاده کنید:

```sh
aether-ctl passwall status            # وضعیت، localhost_proxy و نودهای مرتبط
aether-ctl passwall localhost off     # توقف پروکسی ترافیک خود روتر توسط Passwall2
aether-ctl passwall localhost on      # فعال‌سازی مجدد
aether-ctl passwall add-node          # ساخت تنها نود رسمی: aether_node
```

رفتار:

- دستور `status` همه نودهای loopback از نوع SOCKS که نام یا remarks آن‌ها حاوی
  «aether» است را بررسی می‌کند؛ تطابق دقیق آدرس/پورت با شنونده فعلی Aether به
  عنوان «پیکربندی‌شده» و هر چیز دیگری به عنوان تداخل گزارش می‌شود.
- غیرفعال کردن Localhost Proxy از لوپ مسیریابی جلوگیری می‌کند: تا زمانی که فعال
  است، Passwall2 ترافیک handshake خود هسته Aether را رهگیری می‌کند و تونل هرگز
  بالا نمی‌آید. اگر کلید اصلی Passwall2 روشن باشد، پس از تغییر به‌طور خودکار
  restart می‌شود.
- دستور `add-node` دقیقاً یک نود به نام `aether_node` (نوع Xray، پروتکل socks،
  transport برابر raw) رو به آدرس فعلی Aether می‌سازد و هرگز ورود دوم ایجاد
  نمی‌کند.
- اگر نود مرتبط با Aether از قبل به آدرس/پورت دیگری اشاره کند، چیزی تغییر
  نمی‌کند: در CLI و LuCI دستورالعمل اصلاح دستی نمایش داده می‌شود (ویرایش
  Address/Port همان نود در Services -> Passwall2 -> Nodes یا حذف آن و اجرای
  دوباره `add-node`).

## دستورات CLI

```sh
aether-ctl start
aether-ctl stop
aether-ctl restart
aether-ctl status
aether-ctl show
aether-ctl log 100
aether-ctl test google.com
aether-ctl passwall status            # وضعیت پل Passwall2
aether-ctl passwall localhost off     # غیرفعال کردن پروکسی لوکال‌هاست Passwall2
aether-ctl passwall add-node          # ساخت نود socks اشاره‌کننده به Aether
aether-ctl set protocol wg
aether-ctl set upstream_proxy socks5://192.168.1.9:1082
aether-ctl update
aether-ctl change-version v1.5.0 --start
aether-ctl update --version v1.5.0 --start
```

گزینه Enable on Boot از کنترل runtime جدا است:

```sh
aether-ctl set enabled yes   # فعال‌سازی شروع بعد از ریبوت
aether-ctl set enabled no    # غیرفعال‌سازی شروع بعد از ریبوت
aether-ctl start             # شروع همین حالا، مستقل از تنظیم بوت
aether-ctl stop              # توقف همین حالا، مستقل از تنظیم بوت
```

## نصب و به‌روزرسانی

اسکریپت نصب را با دسترسی root روی روتر اجرا کنید. این اسکریپت باینری مناسب
معماری را دانلود، checksum از نوع SHA-256 را بررسی، فایل‌ها را مرحله‌بندی،
کانفیگ موجود را به صورت پیش‌فرض حفظ، cacheهای LuCI را پاک و سرویس‌های وب لازم
را restart می‌کند.

```sh
wget -qO /tmp/aether-install.sh https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main/install.sh
chmod +x /tmp/aether-install.sh
/tmp/aether-install.sh --start
```

نصب‌کننده حداکثر پنج نسخه پایدار هسته از v1.5.0 به بعد را نمایش می‌دهد و
پیش‌فرض آن v1.7.0 است. برای automation از `--non-interactive` استفاده کنید و
برای نسخه مشخص v1.5.0 به بعد `--version vX.Y.Z` را بدهید. دستور
`aether-ctl update` آخرین updater ریپو را دریافت کرده و همین فرآیند نصب را
اجرا می‌کند؛ `aether-ctl change-version vX.Y.Z` میانبر مشخص برای تغییر نسخه
هسته است. پیش از شروع و پیش از رندر فرم LuCI، نسخه هسته تشخیص داده می‌شود.
در v1.5 گزینه‌های مخصوص v1.6 شامل HTTP CONNECT proxy، MASQUE startup deadline
و کنترل سطح لاگ مخفی شده و به هسته ارسال نمی‌شوند. نسخه‌های v1.6 پروفایل
قابلیت v1.6 را دارند و نسخه‌های v1.7 و جدیدتر علاوه بر آن، زنجیره پروکسی
بالادستی (گزینه `upstream_proxy`) را هم پشتیبانی می‌کنند. در آپدیت، کانفیگ
و هویت‌ها حفظ می‌شوند مگر `--force-config` استفاده شود.

نصب تازه روی `0.0.0.0:1819` گوش می‌دهد تا کلاینت‌های LAN بتوانند استفاده کنند.
چون SOCKS5 احراز هویت ندارد، از firewall استفاده کنید یا برای استفاده فقط روی
روتر، آدرس را به `127.0.0.1:1819` تغییر دهید.

اگر بعد از آپدیت صفحه جدید LuCI را نمی‌بینید، با `Ctrl+F5` صفحه را hard refresh
کنید یا از پنجره incognito/private و یا یک مرورگر جدید استفاده کنید. cache
جاوااسکریپت مرورگر ممکن است صفحه قبلی را نگه دارد.

## حذف نصب

در حذف معمولی، کانفیگ و هویت‌ها باقی می‌مانند:

```sh
wget -qO /tmp/aether-uninstall.sh https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main/uninstall.sh
chmod +x /tmp/aether-uninstall.sh
/tmp/aether-uninstall.sh
```

فقط زمانی از `--purge` استفاده کنید که می‌خواهید `/etc/config/aether` و
`/etc/aether`، شامل هویت‌های ثبت‌شده، نیز حذف شوند.

## عیب‌یابی

- وضعیت سرویس: `aether-ctl status`
- لاگ‌های اخیر: `aether-ctl log 100`
- تست از داخل تونل: `aether-ctl test google.com`
- اگر سرویس روشن است ولی ترافیک عبور نمی‌کند، کمی برای watchdog صبر کنید یا
  `aether-ctl restart` را اجرا کنید.
- اگر LuCI قدیمی است، ابتدا پنجره private یا مرورگر جدید را امتحان کنید.
