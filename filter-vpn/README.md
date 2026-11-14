# Filter VPN

A rule-based SOCKS5 VPN for Android (Java + native C++/NDK).

Filter VPN creates a local VPN with `VpnService`. Connections that match your
rules go through your SOCKS5 proxy. Everything else goes out directly, as if
there were no VPN.

- Package name: `com.vhaiup.filtervpn`
- minSdk 24, targetSdk/compileSdk 36
- License: MIT

> **Status: phase 1 of 4 (skeleton).** The project builds a signed APK with a
> native library, but the VPN engine is not implemented yet. See the
> [roadmap](#roadmap).

---

## Build (Ubuntu VPS)

```bash
git clone <repo-url>
cd <repo>/filter-vpn
cp proxy.properties.example proxy.properties   # optional: pre-filled proxy defaults
./build.sh
```

The script:

1. installs JDK 17, `curl`, `unzip` and `git` with apt (it uses `sudo` when not run as root);
2. downloads the Android command-line tools into `$ANDROID_HOME` (default
   `~/android-sdk`), accepts the licences and installs `platforms;android-36`,
   `build-tools;36.0.0`, `ndk;27.2.12479018` and `cmake;3.22.1`;
3. writes `local.properties` and, on the first run, generates a release
   keystore (`filtervpn-release.jks` + `keystore.properties`, both git-ignored);
4. runs `./gradlew assembleRelease` and copies the APK to
   `dist/FilterVPN-<version>-release.apk`.

| Option | Effect |
|---|---|
| `--debug` | build the debug APK |
| `--test` | also run the JVM unit tests |
| `--abi arm64-v8a` | build only some ABIs (faster, smaller APK) |
| `--skip-deps` | skip apt and sdkmanager |

Requirements: an x86_64 Ubuntu/Debian host, about 6 GB of free disk, at least
2 GB of RAM (4 GB recommended), and access to `dl.google.com`, `maven.google.com`,
Maven Central and `services.gradle.org`.

Keep `filtervpn-release.jks` and `keystore.properties` safe. Android only
installs an update over an existing install if it is signed with the same key.

## Proxy defaults and secrets

You enter the proxy settings in the app, and the app never hardcodes
credentials. To save typing during testing, `proxy.properties`
(git-ignored) can supply defaults that are compiled into *your* build:

```properties
proxy.host=203.0.113.10
proxy.port=1080
proxy.username=user
proxy.password=secret
```

Only `proxy.properties.example` is committed. Do not share an APK that was
built with real credentials in `proxy.properties`.

## Roadmap

| Phase | Scope | State |
|---|---|---|
| 1 | Gradle + CMake skeleton, `build.sh`, signing, CI | ✅ |
| 2 | `VpnService`, package filter, lwIP tun2socks engine, SOCKS5 (RFC 1928/1929) for all traffic, foreground notification | ⏳ |
| 3 | DNS-based domain matching, TLS SNI / HTTP Host sniffing, direct bypass with `protect()`, UDP/DNS handling, IPv6, network change | ⏳ |
| 4 | Full UI (rules editor, app picker, proxy test), connection log, unit tests, full docs | ⏳ |

## Planned architecture

```
 apps ──► TUN (10.111.222.1/30, route 0.0.0.0/0, DNS 10.111.222.2, IPv6 ::/0 blackholed)
            │  packets
            ▼
   native engine (C++, lwIP user-space TCP/IP stack)
    ├─ UDP :53 to 10.111.222.2 ─► DNS resolver: records domain→IP and
    │                             forwards matched names via SOCKS5 (DNS-over-TCP)
    ├─ TCP accept ─► rule decision (DNS map → SNI/Host sniff fallback)
    │       ├─ proxy  ─► SOCKS5 CONNECT (user/pass auth)
    │       └─ direct ─► protect()ed socket to the real destination
    └─ other UDP ─► direct (protect()ed); QUIC to matched domains is dropped → TCP fallback
```

- **Rule modes:** `APP_ONLY`, `DOMAIN_ONLY` or `APP_AND_DOMAIN`. The package list
  (or `*`) is applied with `addAllowedApplication()` / `addDisallowedApplication()`,
  so apps that are not selected never enter the tunnel.
- **Rules** are stored as JSON in SharedPreferences and can be edited in the app.
- **Logging** shows each connection: domain, app and `proxy`/`direct`.

## Project layout

```
filter-vpn/
├── build.sh                      # one-shot Ubuntu build
├── proxy.properties.example      # template for git-ignored defaults
├── app/
│   ├── build.gradle
│   └── src/
│       ├── main/java/com/vhaiup/filtervpn/   # UI, rules
│       ├── main/java/com/vhaiup/vpn/         # VpnService + JNI bridge
│       ├── main/cpp/                         # CMakeLists.txt + native engine
│       └── test/java/                        # JVM unit tests
└── ../.github/workflows/filter-vpn-android.yml
```

## Troubleshooting

- **`sdkmanager failed`** – the host can't reach `dl.google.com`. Check the
  firewall or proxy, then re-run `./build.sh`.
- **Gradle gets killed or `Java heap space`** – the VPS has too little RAM. Add swap:
  `sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`.
- **`INSTALL_FAILED_UPDATE_INCOMPATIBLE`** – the APK was signed with a different
  key than the installed copy. Uninstall the old app first, or keep your
  `filtervpn-release.jks`.
- **ARM VPS** – Google publishes the SDK build-tools for x86_64 Linux only. Build on an x86_64 machine.
