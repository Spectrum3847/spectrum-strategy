use std::time::{SystemTime, UNIX_EPOCH};

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}

fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = year - i64::from(month <= 2);
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let mp = if month > 2 { month - 3 } else { month + 9 };
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

pub fn iso(ms: i64) -> String {
    let (days, rem) = (ms.div_euclid(86_400_000), ms.rem_euclid(86_400_000));
    let (y, mo, d) = civil_from_days(days);
    format!(
        "{y:04}-{mo:02}-{d:02}T{:02}:{:02}:{:02}.{:03}Z",
        rem / 3_600_000,
        rem / 60_000 % 60,
        rem / 1000 % 60,
        rem % 1000
    )
}

fn number(s: &str) -> Option<i64> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

pub fn parse_iso(text: &str) -> Option<i64> {
    let (date, time) = text.split_once(['T', ' '])?;
    let mut d = date.split('-');
    let (y, mo, day) = (number(d.next()?)?, number(d.next()?)?, number(d.next()?)?);
    if d.next().is_some() || !(1..=12).contains(&mo) || !(1..=31).contains(&day) {
        return None;
    }
    let (clock, offset_ms) = match time.find(['Z', '+', '-']) {
        None => (time, 0),
        Some(i) => {
            let (clock, zone) = time.split_at(i);
            if zone == "Z" {
                (clock, 0)
            } else {
                let sign = if zone.starts_with('-') { -1 } else { 1 };
                let (h, m) = zone[1..].split_once(':')?;
                (clock, sign * (number(h)? * 60 + number(m)?) * 60_000)
            }
        }
    };
    let (hms, frac) = clock.split_once('.').unwrap_or((clock, ""));
    let mut t = hms.split(':');
    let (h, mi, s) = (number(t.next()?)?, number(t.next()?)?, number(t.next()?)?);
    if t.next().is_some() || h > 23 || mi > 59 || s > 60 {
        return None;
    }
    let millis = if frac.is_empty() {
        0
    } else if !frac.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    } else {
        number(&format!("{:0<3}", &frac[..frac.len().min(3)]))?
    };
    let secs = days_from_civil(y, mo, day) * 86_400 + h * 3600 + mi * 60 + s;
    Some(secs * 1000 + millis - offset_ms)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_round_trips() {
        for ms in [0, 1_731_242_096_789, 951_782_400_000, 4_102_444_799_999] {
            assert_eq!(parse_iso(&iso(ms)), Some(ms));
        }
    }

    #[test]
    fn iso_known_value() {
        assert_eq!(iso(1_731_242_096_789), "2024-11-10T12:34:56.789Z");
    }

    #[test]
    fn parses_dart_microseconds_and_offsets() {
        let base = parse_iso("2026-11-10T12:00:00.000Z").unwrap();
        assert_eq!(parse_iso("2026-11-10T12:00:00.123456Z"), Some(base + 123));
        assert_eq!(parse_iso("2026-11-10T07:00:00-05:00"), Some(base));
        assert_eq!(parse_iso("2026-11-10T12:00:00"), Some(base));
    }

    #[test]
    fn rejects_garbage() {
        for bad in ["", "yesterday", "2026-13-01T00:00:00Z", "2026-11-10"] {
            assert_eq!(parse_iso(bad), None, "{bad}");
        }
    }
}
