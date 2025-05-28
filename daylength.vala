#!/usr/bin/env -S vala -X -lm -X -O2 -X -march=native -X -pipe

/**
 * Computes solar declination (δ) in radians using NOAA's empirical formula.
 *
 * δ = 0.006918
 *   - 0.399912 * cos(γ)
 *   + 0.070257 * sin(γ)
 *   - 0.006758 * cos(2γ)
 *   + 0.000907 * sin(2γ)
 *   - 0.002697 * cos(3γ)
 *   + 0.001480 * sin(3γ)
 *
 * where γ = 2π * n / days_in_year(year).
 *
 * @param n     Day of year (1..365/366)
 * @param year  Calendar year for days calculation
 * @return Solar declination in radians.
 */
private inline double solar_declination (int n, int year) {
    double days = ((year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0))) ? 366.0 : 365.0;
    double gamma = 2.0 * Math.PI * n / days;
    return 0.006918
        - 0.399912 * Math.cos (gamma)
        + 0.070257 * Math.sin (gamma)
        - 0.006758 * Math.cos (2 * gamma)
        + 0.000907 * Math.sin (2 * gamma)
        - 0.002697 * Math.cos (3 * gamma)
        + 0.00148  * Math.sin (3 * gamma);
}

/**
 * Calculates day length (hours) for a given latitude and date.
 *
 * Uses NOAA solar declination and formula:
 *   T = (24/π) * arccos( -tan(φ) * tan(δ) )
 *
 * φ: observer latitude (radians),
 * δ: solar declination (radians).
 * Returns 24.0 for polar day, 0.0 for polar night.
 *
 * @param latitude_rad Latitude in radians.
 * @param date_obj     GLib.DateTime of observation.
 * @return Day length in hours.
 */
double day_length (double latitude_rad, DateTime date_obj) {
    double phi = latitude_rad;
    int n = date_obj.get_day_of_year (); // nth day of the year
    int year = date_obj.get_year ();
    double delta = solar_declination (n, year);

    double X = - Math.tan (phi) * Math.tan (delta);
    if (X.is_nan ()) {
        // Maybe on some platforms, tan(pi/2) * tan (0) returns NaN
        // This is sprint/autumn equinox of the polar points, so day and night are equal
        return 12.0;
    } else if (X < -1) {
        return 24.0;
    } else if (X > 1) {
        return 0.0;
    } else {
        // 'omega0' is the half-angle (in radians) corresponding to the time from sunrise to solar noon.
        // Since 2π radians represent 24 hours, 1 radian equals 24/(2π) hours.
        // Multiplying omega0 by (24/Math.PI) converts this angle to the total day length in hours.
        double omega0 = Math.acos (X); // computed in radians
        double T = (24.0 / Math.PI) * omega0; // convert to hours
        return T;
    }
}

/**
 * Main entry point.
 * @param args Command line arguments.
 * @return Exit status code.
 */
int main (string[] args) {
    Intl.setlocale ();
    // Define and parse command line arguments
    double latitude_deg = 0; 
    string? date_str = null;
    OptionEntry[] entries = {
        { "latitude", 'l', OptionFlags.NONE, OptionArg.DOUBLE, out latitude_deg,
          "Geographic latitude of observation point (in degrees, positive for North, negative for South)", "latitude" },
        { "date", 'd', OptionFlags.NONE, OptionArg.STRING, out date_str,
          "Date (format: YYYY-MM-DD), defaults to today", "date" },
        null
    };

    OptionContext context = new OptionContext();
    context.set_help_enabled (true);
    context.set_summary ("Calculate daylight duration (in hours) for given date and latitude\n");
    context.add_main_entries (entries, null);

    try {
        context.parse (ref args);
    } catch (Error e) {
        stderr.printf ("Error parsing arguments: %s\n", e.message);
        return 1;
    }

    // Use current date if not provided
    DateTime date_obj;
    if (date_str == null) {
        date_obj = new DateTime.now_local ();
    } else {
        // Complete date string to ISO 8601 format if needed
        string iso_str;
        int pos_T = date_str.index_of_char ('T');
        if (pos_T > 0) {
            iso_str = date_str;
            string tz_part = date_str[pos_T:];
            if (tz_part.index_of_char ('Z') < 0 && tz_part.index_of_char ('+') < 0 && tz_part.index_of_char ('-') < 0) {
                iso_str += "Z"; // Append 'Z' for UTC if no timezone is specified
            }
        } else {
            pos_T = date_str.length;
            iso_str = date_str + "T12:00:00Z";
        }

        date_obj = new DateTime.from_iso8601 (iso_str, null);
        if (date_obj == null) {
            stderr.printf ("Invalid date format: %s\n", date_str);
            return 1;
        }
    }

    double latitude_rad = Math.PI / 180.0 * latitude_deg;
    double T = day_length (latitude_rad, date_obj);
    stdout.printf (
        "%s  |  Latitude: %.2f deg  |  Daylight: %.2f hours\n",
        date_obj.format ("%Y-%m-%d"),
        latitude_deg,
        T
    );
    return 0;
}
