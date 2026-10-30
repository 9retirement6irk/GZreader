"""A CalDAV server for the Calendar tab's tests and the emulator: Radicale
(pip install radicale) with two calendars of sample events around today.

  python3 -I demo_caldav.py PORT WORKDIR

User "reader", password "demo-app-password". Calendars "Personal" and
"Work": one-off events, an all-day event, a three-day trip, a weekly
repeating meeting with one occurrence moved and one cancelled, a monthly
event on the first Tuesday, and an event with a time zone (TZID).
Prints "caldav ready" once seeded.
"""
import os, sys, time, signal, subprocess, urllib.request, base64
from datetime import datetime, timedelta, timezone

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18095
WORK = sys.argv[2] if len(sys.argv) > 2 else "/tmp/caldav-demo"
USER, PASSWORD = "reader", "demo-app-password"

os.makedirs(WORK, exist_ok=True)
with open(os.path.join(WORK, "users"), "w") as f:
    f.write(f"{USER}:{PASSWORD}\n")
with open(os.path.join(WORK, "config"), "w") as f:
    f.write(f"""[server]
hosts = 127.0.0.1:{PORT}
[auth]
type = htpasswd
htpasswd_filename = {WORK}/users
htpasswd_encryption = plain
[storage]
filesystem_folder = {WORK}/collections
[logging]
level = warning
""")
server = subprocess.Popen([sys.executable, "-m", "radicale", "--config", os.path.join(WORK, "config")])


def stop(*_args):
    server.terminate()
    sys.exit(0)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

AUTH = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
BASE = f"http://127.0.0.1:{PORT}"


def req(method, path, body=None, ctype="application/xml; charset=utf-8"):
    r = urllib.request.Request(BASE + path, data=body.encode() if body else None, method=method)
    r.add_header("Authorization", AUTH)
    if body:
        r.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(r, timeout=10) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code


for _ in range(50):
    try:
        if req("PROPFIND", "/") in (207, 200, 401, 404):
            break
    except Exception:
        time.sleep(0.2)

today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)


def local(days, hour=0, minute=0):
    return today + timedelta(days=days, hours=hour, minutes=minute)


def fmt_local(dt):
    return dt.strftime("%Y%m%dT%H%M%S")


def fmt_utc(dt):
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def fmt_date(dt):
    return dt.strftime("%Y%m%d")


def mkcal(name, display, color):
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:I="http://apple.com/ns/ical/">
 <D:set><D:prop><D:displayname>{display}</D:displayname><I:calendar-color>{color}</I:calendar-color>
 <C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set></D:prop></D:set>
</C:mkcalendar>"""
    return req("MKCALENDAR", f"/{USER}/{name}/", body)


def put(cal, uid, vevent):
    ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//GZreader demo//EN\r\n" + vevent.strip().replace("\n", "\r\n") + "\r\nEND:VCALENDAR\r\n"
    return req("PUT", f"/{USER}/{cal}/{uid}.ics", ics, "text/calendar; charset=utf-8")


req("MKCOL", f"/{USER}/")
mkcal("personal", "Personal", "#2E7D32")
mkcal("work", "Work", "#1565C0")

# Personal
put("personal", "dentist", f"""BEGIN:VEVENT
UID:dentist
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART:{fmt_utc(local(0, 15, 30))}
DTEND:{fmt_utc(local(0, 16, 15))}
SUMMARY:Dentist
LOCATION:Main St Dental, 12 Main St
DESCRIPTION:Bring the insurance card.\\nCheck-up and cleaning.
END:VEVENT""")
put("personal", "birthday", f"""BEGIN:VEVENT
UID:birthday
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART;VALUE=DATE:{fmt_date(local(2))}
DTEND;VALUE=DATE:{fmt_date(local(3))}
SUMMARY:Mom's birthday
END:VEVENT""")
put("personal", "trip", f"""BEGIN:VEVENT
UID:trip
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART;VALUE=DATE:{fmt_date(local(9))}
DTEND;VALUE=DATE:{fmt_date(local(12))}
SUMMARY:Hiking: Springer Mountain
LOCATION:Amicalola Falls State Park
END:VEVENT""")
put("personal", "bookclub", f"""BEGIN:VEVENT
UID:bookclub
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART;TZID=America/New_York:{fmt_local(local(1, 19))}
DTEND;TZID=America/New_York:{fmt_local(local(1, 20, 30))}
SUMMARY:Book club: A Walk in the Woods
LOCATION:Library, room 2
END:VEVENT""")
put("personal", "run", f"""BEGIN:VEVENT
UID:run
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART:{fmt_utc(local(0, 7))}
DTEND:{fmt_utc(local(0, 7, 45))}
RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=30
SUMMARY:Morning run
END:VEVENT""")

# Work: a weekly meeting, one occurrence moved, one cancelled. Its start is in
# UTC, so the moved / cancelled occurrences are counted in UTC too (a local
# date + 7 days is an hour off across a daylight-saving change).
start = local(1, 10).astimezone(timezone.utc)
put("work", "standup", f"""BEGIN:VEVENT
UID:standup
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART:{fmt_utc(start)}
DTEND:{fmt_utc(start + timedelta(minutes=30))}
RRULE:FREQ=WEEKLY;INTERVAL=1
EXDATE:{fmt_utc(start + timedelta(days=14))}
SUMMARY:Team meeting
LOCATION:Room 4B
END:VEVENT
BEGIN:VEVENT
UID:standup
DTSTAMP:{fmt_utc(datetime.now())}
RECURRENCE-ID:{fmt_utc(start + timedelta(days=7))}
DTSTART:{fmt_utc(start + timedelta(days=7, hours=4))}
DTEND:{fmt_utc(start + timedelta(days=7, hours=4, minutes=30))}
SUMMARY:Team meeting (moved to the afternoon)
LOCATION:Room 4B
END:VEVENT""")
put("work", "review", f"""BEGIN:VEVENT
UID:review
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART:{fmt_utc(local(0, 13))}
DTEND:{fmt_utc(local(0, 14, 30))}
SUMMARY:Quarterly review
END:VEVENT""")
put("work", "allhands", f"""BEGIN:VEVENT
UID:allhands
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART:{fmt_utc(local(-today.day + 1, 9))}
DTEND:{fmt_utc(local(-today.day + 1, 10))}
RRULE:FREQ=MONTHLY;BYDAY=1TU
SUMMARY:All hands
END:VEVENT""")
put("work", "conf", f"""BEGIN:VEVENT
UID:conf
DTSTAMP:{fmt_utc(datetime.now())}
DTSTART:{fmt_utc(local(4, 9))}
DTEND:{fmt_utc(local(4, 17))}
SUMMARY:Conference talk: e-ink interfaces
LOCATION:Convention Center, hall C
END:VEVENT""")
print("caldav ready", flush=True)
server.wait()
