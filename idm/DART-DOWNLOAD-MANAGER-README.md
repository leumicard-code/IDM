# 🚀 Dart Download Manager — Resume + Multi-Connection

> מוריד קבצים מהר, עם חידוש הורדה (Resume) ו-8 חיבורים מקבילים. לא טנק רוסי.

### ✨ מה זה עושה
- **Multi-Connection (8 חלקים):** מחלק את הקובץ ל-8 ומוריד במקביל — מהיר פי 8
- **Resume אמיתי:** אם האינטרנט נפל או סגרת את הטרמינל, מריץ שוב וממשיך מאיפה שנעצרת — בודק `*.part0...part7`
- **Retry חכם:** 10 ניסיונות עם `exponential backoff` — `1s, 2s, 4s...`
- **Progress Bar חי:** `████── 68.5% 124.3/181.5 MB  19.2 MB/s`
- **Fallback:** אם השרת לא תומך ב-`Range: bytes` — עובר להורדה רגילה אוטומטית

### 📦 התקנה
```bash
dart pub add dio path
```

### 🔥 שימוש
```bash
dart download.dart <URL> [שם_קובץ]

# דוגמאות:
dart download.dart https://example.com/big.iso
dart download.dart https://example.com/video.mp4 my_video.mp4
```

### 🧠 איך זה עובד
1. `HEAD` — בודק `content-length` ו-`accept-ranges: bytes`
2. מחלק: `partSize = ceil(total / 8)`
3. לכל חלק: `Range: bytes=start-end` עם `FileAccessMode.append`
4. כל חלק שומר ל-`savePath.part{i}` — אם קיים, ממשיך ממנו
5. בסוף: מחבר את כל ה-`*.part` לקובץ אחד ומוחק את הזמניים

```
[part0: ████ 25MB][part1: ████ 25MB][part2: ██── 12MB] -> file.iso
```

### ⚡ ביצועים
- 8 חיבורים מקבילים
- Resume — לא מוריד שוב מהתחלה
- מהירות: מודד `KB/s` / `MB/s` בזמן אמת
- Timeout: connect 20s, receive 30min

### 🛠 קוד איכותי
- Dart null-safe
- `Dio` עם `User-Agent: DartDownloadManager/1.1`
- `existingBytes` — לא דורס קבצים
- `min((i+1)*partSize-1, contentLength-1)` — גבולות בטוחים

### 📊 דוגמת פלט
```
🚀  Dart Download Manager (with Resume)
URL:        https://example.com/big.zip
קובץ:       big.zip
חיבורים:    8

גודל קובץ: 181.50 MB
Resume:      פעיל

ממשיך הורדה קודמת... (42.1 MB כבר ירדו)

███████─ 78.5%  142.5/181.5 MB  12.4 MB/s
Range: 0-... (attempt 1/10)

מחבר חלקים...
סיום! זמן: 12s | ממוצע: 15.1 MB/s
✓ ההורדה הסתיימה בהצלחה
```

### 💡 למה זה שווה כסף?
כמו `syseq` — 16.2 MiB, 60 MiB RAM, 0.3% CPU — קליל, עושה עבודה אחת הכי טוב. לא טנק רוסי כמו IDM.

---
**Built with Dart + Dio • Resume • 8 Connections • Retry**
**RUST eats everything, Dart downloads everything**
