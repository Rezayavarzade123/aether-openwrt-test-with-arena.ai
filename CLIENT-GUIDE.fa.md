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
- **MASQUE-in-MASQUE (mim، هسته v2+)**: دو مرحله MASQUE دارد و می‌تواند IP خروجی
  متفاوتی بسازد. از کشف خودکار یا endpoint بیرونی/درونی صریح پشتیبانی می‌کند و
  تنظیمات HTTP/2، fragmentation، ECH و QUIC v2 مربوط به MASQUE را به اشتراک
  می‌گذارد. دو endpoint ثابت باید متفاوت باشند؛ MIM به ثبت هویت دوم و یک رفت‌وبرگشت
  اضافه نیز نیاز دارد.

کلاینت endpointها را اسکن کرده و قبل از باز کردن SOCKS5، عبور واقعی داده را
بررسی می‌کند. گزینه **Quick Reconnect** ابتدا endpoint موفق قبلی را بررسی
می‌کند تا در صورت امکان از اسکن کامل جلوگیری شود.

## تنظیمات

### تنظیمات پایه و شبکه

- **Enable on Boot** فقط شروع خودکار بعد از ریبوت روتر را کنترل می‌کند و مانع
  استفاده از دکمه‌های Start و Stop یا دستورات CLI در زمان فعلی نمی‌شود.
- **Scan Mode**: حالت `turbo` سریع‌تر است؛ `balanced` انتخاب معمول است؛
  حالت‌های `thorough`، `stealth` و `ironclad` زمان بیشتری برای کشف یا اعتبارسنجی
  صرف می‌کنند. حالت `verified` (هسته v2.1+) فقط به لبه‌های سنجیده‌شده‌ای وصل
  می‌شود که connect-ip را جواب داده باشند.
- **IP Version**: اگر IPv6 روی روتر فعال و سالم نیست، IPv4 را انتخاب کنید.
- **Force Peer**: با وارد کردن `ip:port` اسکن را رد می‌کند.
- **Exit Location Policy** (هسته v2.1+): تونلی که کشور خروجش مطلوب نباشد را رد
  می‌کند (مثلاً `!IR,AZ,RU`)؛ هر دقیقه از داخل تونل دوباره بررسی می‌شود.
- **Traffic Stats Logging** (هسته v2.1+): ثبت حجم آپلود/دانلود و مدت بالابودن
  تونل هر ۶۰ ثانیه.
- **HTTP/2 Mode** و **H2 Peer** برای MASQUE و MIM هستند. وقتی UDP/QUIC مسدود است
  از HTTP/2 استفاده کنید.
- **TLS Fragmentation** برای MASQUE/MIM روی HTTP/2 و در صورت مسدود بودن handshake است.
- **QUIC v2 Opener** (هسته v2+) به‌صورت پیش‌فرض برای MASQUE/MIM روی HTTP/3 فعال
  است؛ فقط وقتی با شبکه شما ناسازگار است آن را غیرفعال کنید.
- **Encrypted Client Hello (ECH)** (هسته v1.9+) مقدار `auto` یا پیکربندی base64
  می‌پذیرد. برای حفظ پیش‌فرض هسته آن را خالی بگذارید.
- **HTTP CONNECT Proxy** به‌صورت اختیاری همان تونل را برای برنامه‌های بدون SOCKS5
  فراهم می‌کند.
- **Upstream Proxy** (نیازمند هسته v1.7+) تونل را پشت یک پروکسی دیگر زنجیر
  می‌کند. مقدار آن می‌تواند `socks5://[user:pass@]host:port`، `http://host:port`
  یا فقط `host:port` (SOCKS5 در نظر گرفته می‌شود) باشد. پروکسی SOCKS5 بالادستی
  همه transportها را پشتیبانی می‌کند؛ پروکسی HTTP CONNECT به حالت HTTP/2 نیاز
  دارد. این مقدار مستقیماً از طریق پرچم `--upstream` به هسته داده می‌شود و در
  `aether-ctl show` مخفی (redact) نمایش داده می‌شود.
- **MASQUE Startup Deadline** برای اتصال و اولین اعتبارسنجی داده در MASQUE/MIM
  محدودیت زمانی می‌گذارد و مقدار پیش‌فرض آن ۳۰ ثانیه است.
- **Disable Profile Retry** برای WireGuard/gool/MIM است و تلاش دوباره با پروفایل
  noise دیگر را پس از اسکن ناموفق متوقف می‌کند.

### تنظیمات پایداری

- **Keepalive** برای WireGuard، gool و MIM استفاده می‌شود.
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

## پروفایل عملکرد (هسته v1.8+)

هسته v1.8 پروفایل منابع (`--perf low|medium|high`) را معرفی کرد. در هنگام نصب،
اسکریپت `install.sh` رم کل روتر را بررسی کرده و مقدار اولیه را در `/etc/config/aether`
تنظیم می‌کند. کاربران می‌توانند آن را در LuCI (بخش Advanced گزینه **Performance Profile**:
`Low`، `Medium`، `High`) یا از طریق `aether-ctl set perf_profile low|medium|high`
تغییر دهند. برای تشخیص خودکار مجدد بر اساس رم، دستور `aether-ctl auto-perf` را اجرا کنید:
| مجموع رم | پروفایل |
| --- | --- |
| کمتر از 256 MB | `low` |
| 256 تا 768 MB | `medium` |
| بیش از 768 MB | `high` |

اندازه‌گیری روی هسته v1.9.0 (x86_64؛ نمونه‌برداری VmRSS هر ثانیه؛ در هر اجرا
دانلود 50 مگابایتی به‌همراه آپلود 5 مگابایتی PUT — endpoint مشترک `__up`
پس از بخشی از بدنه، آپلود را reset می‌کند که بر اوج حافظه مبتنی بر بافر اثر
ندارد):

| پروتکل | پروفایل | اوج دانلود | اوج آپلود |
| --- | --- | --- | --- |
| MASQUE | low | 10.2 MB | 9.8 MB |
| MASQUE | medium | 15.9 MB | 12.6 MB |
| MASQUE | high | 22.6 MB | 12.3 MB |
| WireGuard | low | 7.9 MB | 7.6 MB |
| WireGuard | medium | 12.9 MB | 11.2 MB |
| WireGuard | high | 20.0 MB | 10.7 MB |
| gool | low | 7.8 MB | 7.7 MB |
| gool | medium | 13.4 MB | 11.2 MB |
| gool | high | 20.9 MB | 10.9 MB |

مصرف حافظه اوج به پروفایل بستگی دارد نه به پروتکل؛ RSS در حالت بی‌کاری برای همه
حالت‌ها حدود 5.6 تا 7.1 مگابایت است. آستانه‌های بالا برای روترهای با رم کمتر،
حاشیه امن کافی دارند.

قوانین مسیریابی (`--route-block`، `--route-direct`)، DNS سفارشی درون‌تونل،
firewall mark و گروه‌های TLS key-share عمداً توسط این کلاینت ارائه نمی‌شوند.
ابزارهای پروکسی شفاف مانند Passwall2 روی همان روتر تقسیم ترافیک را بهتر انجام
می‌دهند و باقی کنترل‌ها روی پیش‌فرض هسته می‌مانند.

## endpointهای gool دو مرحله‌ای (هسته v1.9+)

هسته v1.9 امکان تعیین مستقل هر یک از دو مرحله WARP-in-WARP را می‌دهد. در LuCI
فیلدهای **gool Outer Hop** / **gool Inner Hop** هنگام انتخاب پروتکل `gool`
نمایش داده می‌شوند (بخش Advanced)؛ در خط فرمان:

```sh
aether-ctl set wiw_outer 162.159.192.1:2408
aether-ctl set wiw_inner 188.114.96.1:2408
aether-ctl set wiw_outer auto   # بازگشت به اسکن خودکار
```

با تعیین یکی از دو مرحله، هسته فقط برای مرحله دیگر اسکن می‌کند؛ با تعیین هر دو
هیچ اسکنی اجرا نمی‌شود. مقدار `auto` (یا خالی) رفتار پیش‌فرض یعنی اسکن هر دو
مرحله را برمی‌گرداند. مرحله‌ای که دستی تعیین شده در اتصال مجدد دوباره تلاش
می‌شود و با نود اسکن‌شده جایگزین نمی‌گردد.

## MASQUE-in-MASQUE، QUIC v2 و Tor (هسته v2+)

هسته v2 پروتکل `mim`، یعنی یک تونل MASQUE داخل تونل MASQUE دیگر، را اضافه می‌کند.
در صورت نیاز endpointهای ثابت را با `mim_outer`، `mim_inner` یا `mim_peers`
تنظیم کنید؛ در غیر این صورت هسته آن‌ها را انتخاب می‌کند. `quic_v2` به‌صورت
پیش‌فرض فعال است و فقط هنگام غیرفعال شدن به `--no-quic-v2` تبدیل می‌شود.

Tor با `tor_mode` در دسترس است:

- `tunnel` شنونده SOCKS5 معمول WARP را نگه می‌دارد و یک شنونده Tor اضافه می‌کند؛
  ترافیک Tor از WARP عبور می‌کند.
- `reverse` به MASQUE از مسیر Tor می‌رسد و با WARP خارج می‌شود؛ به MASQUE و
  HTTP/2 نیاز دارد.
- `only` Tor را روی شنونده SOCKS5 اصلی ارائه می‌کند و تونل WARP برقرار نمی‌شود.

این کنترل‌ها فقط در هسته v2 ظاهر می‌شوند و به بسته هسته‌ای نیاز دارند که با
قابلیت Tor و transportهای افزونه لازم ساخته شده باشد. کلاینت کنترل‌ها را بر پایه
نسخه نمایش می‌دهد و وجود قابلیت Tor در build نصب‌شده را از پیش بررسی نمی‌کند.
`reverse` فقط با پروتکل MASQUE مجاز است و CLI تغییر ناسازگار را در هر دو جهت رد
می‌کند.

پنل Status وضعیت پیکربندی‌شده `Tor` را نشان می‌دهد (`Enabled at <bind>`،
`Disabled` یا `Needs core v2.0+`)؛ این وضعیت به‌تنهایی نشانه bootstrap موفق Tor
نیست. دکمه **Check Tor IP** خروجی واقعی را از طریق
`https://check.torproject.org/api/ip` بررسی می‌کند. معادل CLI آن:

```sh
aether-ctl check-tor        # IP خروجی و وضعیت IsTor (نام مستعار: tor-ip)
```

`tor_bind` (پیش‌فرض `127.0.0.1:1820`) و `tor_dir` شنونده و دایرکتوری state را
تنظیم می‌کنند؛ `tor_bridges` با مقدارهای `auto`/`on`/`off` fallback پل‌ها را برای
شبکه‌های مسدود کنترل می‌کند. بررسی CLI محدود به ۸ ثانیه اتصال و ۲۲ ثانیه کل است؛
بنابراین مدارهای کند `FAILED` می‌دهند، نه خطای transport در LuCI. در حالت فرمان
دستی، اگر آرگومان‌ها `--tor` نداشته باشند، `check-tor` فوری رد می‌شود.

اگر شنونده Tor اتصال می‌پذیرد اما bootstrap تمام نمی‌شود، در
`logread -e aether` دنبال `problem with filesystem permissions` بگردید. Arti
state را وقتی والدهای آن root-owned نباشند یا برای گروه/دیگران قابل نوشتن باشند
رد می‌کند. سرویس هنگام هر شروع Tor، مالکیت و modeهای `/` و `/etc` را ترمیم می‌کند.

### موارد افزوده Tor در هسته v2.1+

با هسته v2.1.0 و جدیدتر، دو کنترل اضافی کنار تنظیمات Tor ظاهر می‌شود:

- `tor_http` علاوه بر SOCKS5، Tor را به شکل پروکسی HTTP/CONNECT روی آدرس
  داده‌شده هم سرو می‌کند؛ برای کلاینت‌هایی که SOCKS5 ندارند.
- `tor_relays` منبع پل‌ها را انتخاب می‌کند: `auto` (پیش‌فرض) پل‌های bridgedb و
  رله‌های onionoo را با هم می‌گیرد، `only` فقط رله‌ها، `off` رله‌ها را غیرفعال
  می‌کند و یک عدد (مثلاً `80`) تعداد رله‌های سنجیده‌شده را تعیین می‌کند. در
  شبکه‌هایی که Tor را مسدود می‌کنند، هسته v2.1+ پل‌ها را از داخل خود تونل
  می‌گیرد و همین است که Tor را در چون شبکه‌ای ممکن می‌کند.

## Psiphon (هسته v2.1+)

هسته v2.1 کتابخانه Psiphon را همان‌طور که Tor را دارد، داخلی دارد و با
`psiphon_mode` سه حالت دارد:

- `tunnel` وزش Psiphon را داخل WARP حمل می‌کند: شنونده SOCKS5 معمول خروجی WARP
  را نگه می‌دارد و شنونده دومی روی `psiphon_bind` (پیش‌فرض `127.0.0.1:1821`)
  از Psiphon خارج می‌شود.
- `reverse` تونل را از مسیر Psiphon شماره‌گیری می‌کند تا WARP از خروجی Psiphon
  دیده شود؛ به پروتکل MASQUE نیاز دارد (Psiphon فقط TCP حمل می‌کند، پس هسته
  MASQUE را روی HTTP/2 اجرا می‌کند) و مانند Tor reverse، روی بقیه پروتکل‌ها در
  هر دو جهت در زمان `set` رد می‌شود.
- `only` Psiphon ساده را روی شنونده SOCKS5 اصلی سرو می‌کند و تونل WARP برقرار
  نمی‌کند.

چیز دیگری لازم نیست: اعتبارنامه‌ها و فهرست سرورها داخل هسته ساخته شده‌اند و
آرشیوهای رسمی ریلیز، برنامه کمکی `psiphon-tunnel-core` را در پوشه `pt/` کنار
باینری می‌گذارند (نصب‌کننده آن را در `/usr/bin/pt` نگه می‌دارد). تنظیم اختیاری:
`psiphon_region` خروجی در یک کشور دوحرفی می‌خواهد (مثلاً `DE`)، `psiphon_shape`
به `--psiphon-mode` نگاشت می‌شود (`auto` پیش‌فرض، `cdn` فقط meek از CDN،
`direct` بدون fronting) و `psiphon_http` Psiphon را به شکل پروکسی
HTTP/CONNECT هم سرو می‌کند. خروجی را با دکمه **Check Psiphon IP** در LuCI یا
با این دستور بررسی کنید:

```sh
aether-ctl set psiphon_mode tunnel
aether-ctl restart
aether-ctl check-psiphon   # IP خروجی Psiphon (نام مستعار: psiphon-ip)
```

## محدودسازی کشور خروج و آمار ترافیک (هسته v2.1+)

`exit_loc` تونلی که کشور خروجش مطلوب نباشد را رد می‌کند: `!IR,AZ,RU` آن کشورها
را مسدود می‌کند و `DE,SE` فقط همان‌ها را می‌پذیرد. این بررسی از داخل تونلِ
تکمیل‌شده، پیش از باز شدن SOCKS5 و سپس هر دقیقه یک‌بار انجام می‌شود؛ پس تونلی
که جابه‌جا شود کنار گذاشته و جایگزین می‌شود. خالی بگذارید (پیش‌فرض) تا هیچ
جست‌وجویی انجام نشود.

`stats` (پیش‌فرض خاموش) هر ۶۰ ثانیه حجم آپلود/دانلود و مدت بالابودن تونل را در
لاگ سرویس می‌نویسد؛ با `logread -f -e aether` ببینید.

## انتخاب حامل gool (هسته v2.3+)

هسته v2.3 معنای `--gool` را عوض کرد: اکنون تونل WARP از نوع WireGuard را داخل
MASQUE حمل می‌کند و هویتش را از داخل تونل ثبت می‌کند تا آدرس خروج خارجی باشد.
حمل‌ونقل قدیمی WireGuard-in-WireGuard با حامل کلاسیک در دسترس می‌ماند:

- `gool_carrier=masque` (پیش‌فرض) از `--gool` جدید استفاده می‌کند؛ `gool_peer`
  می‌تواند endpoint داخلی WireGuard را ثابت کند.
- `gool_carrier=classic` با `--gool-classic` از endpointهای کلاسیک
  WARP-in-WARP با `wiw_outer`/`wiw_inner` استفاده می‌کند.

روی هسته‌های قدیمی‌تر از v2.3 این انتخاب نادیده گرفته می‌شود و gool کلاسیک
می‌ماند. چون نام‌بردن از هر endpoint `wiw_*` باعث می‌شود هسته v2.3+ خودش حامل
کلاسیک را انتخاب کند، کلاینت مقادیر ذخیره‌شده `wiw_*` را فقط وقتی حامل کلاسیک
انتخاب شده به هسته می‌فرستد و با حامل MASQUE در لاگ سرویس به‌عنوان نادیده‌گرفته‌شده
گزارش می‌شود.

## خط فرمان سفارشی

بخش **Custom Command** (آخرین بخش صفحه LuCI) خط فرمان هسته را در اختیار شما
می‌گذارد. در حالت **Generated** (پیش‌فرض)، فرمان فعلی گزارش‌شده توسط procd فقط
خواندنی است. برای دیدن فرمان تولیدشده جدید، پس از restart صفحه را تازه‌سازی کنید.
در حالت **Manual**، یک کادر بزرگ آرگومان‌های خودتان را می‌پذیرد:

- آرگومان‌ها با فاصله جدا شوند؛ از نقل‌قول و قابلیت‌های shell استفاده نکنید؛
- ابتدای `/usr/bin/aether` یا `/usr/bin/aether-run` خودکار حذف می‌شود تا بتوانید
  کل فرمان نمایش‌داده‌شده را paste کنید؛
- ورودی خالی با ثبت لاگ به پرچم‌های تولیدشده برمی‌گردد؛
- اجرا همچنان از طریق `aether-run` است؛ پس secretهای Zero Trust در environment
  باقی می‌مانند و در فهرست پردازه‌ها نمی‌آیند؛
- تغییر پس از restart اعمال و در UCI با `command_mode` و `custom_command` ذخیره
  می‌شود؛ `auto` مقدار دوم را در CLI پاک می‌کند.

حالت Manual همه گزینه‌های UCI، از جمله پروتکل، Tor و bindها را دور می‌زند.
`test`، `check-ip` و `check-tor` به‌جای UCI، bindهای فرمان دستی را می‌خوانند.
CLI مقدارها را پیش از ذخیره اعتبارسنجی می‌کند (`tor_bind` به شکل `ip:port`،
`tor_dir` مسیر مطلق، و `reverse` فقط با MASQUE) و `status`/`show` پروفایل
obfuscation مؤثر را نشان می‌دهند؛ مثلاً `balanced (stored firewall)` وقتی مقدار
ذخیره‌شده برای خانواده پروتکل remap شده است.

## دستورات CLI

```sh
aether-ctl start
aether-ctl stop
aether-ctl restart
aether-ctl status
aether-ctl show
aether-ctl log 100
aether-ctl test google.com
aether-ctl check-ip                     # IP عمومی، کشور و تأخیر
aether-ctl check-tor                    # IP خروجی Tor و IsTor (حالت‌های Tor در v2+)
aether-ctl check-psiphon                # IP خروجی Psiphon (حالت‌های Psiphon در v2.1+)
aether-ctl passwall status            # وضعیت پل Passwall2
aether-ctl passwall localhost off     # غیرفعال کردن پروکسی لوکال‌هاست Passwall2
aether-ctl passwall add-node          # ساخت نود socks اشاره‌کننده به Aether
aether-ctl set protocol wg
aether-ctl auto-perf                      # تشخیص خودکار رم و تنظیم پروفایل بهینه (هسته v1.8+)
aether-ctl set perf_profile medium       # یا تنظیم دستی: low / medium / high (هسته v1.8+)
aether-ctl set wiw_outer 162.159.192.1:2408   # مرحله بیرونی gool (v1.9+؛ حامل کلاسیک در v2.3+)
aether-ctl set wiw_inner 188.114.96.1:2408    # مرحله درونی gool (v1.9+؛ حامل کلاسیک در v2.3+)
aether-ctl set protocol mim                     # MASQUE-in-MASQUE (هسته v2+)
aether-ctl set quic_v2 off                      # غیرفعال‌سازی opener QUIC v2 (هسته v2+)
aether-ctl set ech auto                         # فعال‌سازی کشف ECH (هسته v1.9+)
aether-ctl set tor_mode tunnel                  # Tor از طریق WARP (هسته v2+)
aether-ctl set tor_relays only                  # رله‌های onionoo به‌عنوان پل (v2.1+)
aether-ctl set psiphon_mode tunnel              # Psiphon از طریق WARP (v2.1+)
aether-ctl set psiphon_region DE                # درخواست خروجی Psiphon در آلمان (v2.1+)
aether-ctl set exit_loc '!IR,AZ,RU'             # رد کردن خروجی در آن کشورها (v2.1+)
aether-ctl set stats 1                          # ثبت آمار ترافیک (v2.1+)
aether-ctl set gool_carrier classic             # gool کلاسیک WARP-in-WARP (v2.3+)
aether-ctl set gool_peer 188.114.97.1:2408      # endpoint داخلی gool روی MASQUE (v2.3+)
aether-ctl set command_mode manual               # آرگومان‌های سفارشی هسته
aether-ctl set custom_command '--bind 0.0.0.0:1819 --wg'  # آرگومان‌های جداشده با فاصله
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
wget -qO /tmp/aether-install.sh https://raw.githubusercontent.com/Rezayavarzade123/aether-openwrt-test-with-arena.ai/main/install.sh
chmod +x /tmp/aether-install.sh
/tmp/aether-install.sh --start
```

نصب‌کننده حداکثر پنج نسخه پایدار هسته از v1.5.0 به بعد را نمایش می‌دهد و
پیش‌فرض آن v2.3.0 است. برای automation از `--non-interactive` استفاده کنید و
برای نسخه مشخص v1.5.0 به بعد `--version vX.Y.Z` را بدهید. دستور
`aether-ctl update` آخرین updater ریپو را دریافت کرده و همین فرآیند نصب را
اجرا می‌کند؛ `aether-ctl change-version vX.Y.Z` میانبر مشخص برای تغییر نسخه
هسته است. روی شبکه‌هایی که GitHub تایم‌اوت می‌دهد، گزینه `--mirror <prefix>`
را اضافه کنید (مانند `--mirror https://ghproxy.net/`) یا `AETHER_GH_MIRROR` را
تنظیم کنید تا آرشیو هسته، checksum و فایل‌های پشتیبان از این مسیر دریافت شوند؛
دانلود checksum علاوه بر سه بار تلاش دوباره، به `SHA256SUMS.txt` ریلیز
fallback می‌کند. پیش از شروع و پیش از رندر فرم LuCI، نسخه هسته تشخیص داده می‌شود.
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
wget -qO /tmp/aether-uninstall.sh https://raw.githubusercontent.com/Rezayavarzade123/aether-openwrt-test-with-arena.ai/main/uninstall.sh
chmod +x /tmp/aether-uninstall.sh
/tmp/aether-uninstall.sh
```

فقط زمانی از `--purge` استفاده کنید که می‌خواهید `/etc/config/aether` و
`/etc/aether`، شامل هویت‌های ثبت‌شده، نیز حذف شوند.

## عیب‌یابی

- وضعیت سرویس: `aether-ctl status`
- لاگ‌های اخیر: `aether-ctl log 100`
- تست از داخل تونل: `aether-ctl test google.com`
- بررسی خروجی: `aether-ctl check-ip`؛ برای Tor: `aether-ctl check-tor`
- اگر سرویس روشن است ولی ترافیک عبور نمی‌کند، کمی برای watchdog صبر کنید یا
  `aether-ctl restart` را اجرا کنید.
- اگر Tor روی `:1820` گوش می‌دهد اما وصل نمی‌شود، در لاگ دنبال
  `problem with filesystem permissions` بگردید. سرویس در شروع Tor مالکیت و mode
  `/` و `/etc` را ترمیم می‌کند؛ bootstrap Tor، به‌خصوص روی تونل چندمرحله‌ای، ممکن
  است چند دقیقه طول بکشد.
- در حالت فرمان دستی، هسته دقیقاً آرگومان‌های شما را اجرا می‌کند؛ نبودن `--tor`
  یعنی حتی با `tor_mode=tunnel` نیز Tor اجرا نمی‌شود. مسیر باینری در ابتدای
  فرمان paste‌شده حذف می‌شود تا دوبار ارسال نشود.
- اگر `aether-ctl test <host>` صفحه راهنما را چاپ می‌کند، `aether-ctl` نصب‌شده
  قدیمی و فاقد dispatch مربوط به `test` است؛ فایل‌های کلاینت را به‌روزرسانی کنید.
- استقرار overlay پوشه `files/` با root می‌تواند modeهای `/` و `/etc` را از tar
  بازنویسی کند (tarهای ویندوز ممکن است `0777` ذخیره کنند). سپس سرویس را restart
  کنید تا ترمیم Tor اجرا شود.
- صفحه خالی LuCI همراه با `TypeError: Class must be a descendant of
  CBIAbstractValue` معمولاً یعنی صفحه cache شده به widgetی اشاره می‌کند که در
  `form.js` وجود ندارد؛ با `Ctrl+F5` hard refresh کنید.
- اگر LuCI قدیمی است، ابتدا پنجره private یا مرورگر جدید را امتحان کنید.
