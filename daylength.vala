#!/usr/bin/env -S vala -X -lm -X -pipe -X -O2 -X -march=native

/**
 * Computes solar declination in radians using an approximate formula.
 *
 * Formula: δ (rad) = (23.44 * π/180) * sin(2π/365 * (n - 81))
 *
 * @param n The day number in the year.
 * @return Solar declination in radians.
 */
 private inline double solar_declination (int n) {
    return (23.44 * Math.PI / 180.0) * Math.sin (2 * Math.PI / 365.0 * (n - 81));
}

/**
 * Calculates the day length (in hours) for a given latitude and date.
 *
 * Using formula: T = (2/15) * arccos( -tan(φ) * tan(δ) )
 *
 * φ: observer's latitude, δ: solar declination
 *
 * When |tan φ * tan δ| > 1, returns polar day (24 hours) or polar night (0 hours)
 *
 * @param latitude Geographic latitude in degrees.
 * @param date_obj DateTime object representing the date.
 * @return Day length in hours.
 */
double day_length (double latitude_rad, DateTime date_obj) {
    double phi = latitude_rad;
    int n = date_obj.get_day_of_year (); // nth day of the year
    double delta = solar_declination (n);

    double X = - Math.tan (phi) * Math.tan (delta);
    if (X < -1) {
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
        date_obj = new DateTime.from_iso8601 (date_str, null);
        if (date_obj == null) {
            stderr.printf ("Invalid date format: %s\n", date_str);
            return 1;
        }
    }

    double latitude_rad = latitude_deg * Math.PI / 180.0;
    double T = day_length (latitude_rad, date_obj);
    stdout.printf (
        "%s  |  Latitude: %.2f deg  |  Daylight: %.2f hours\n",
        date_obj.format ("%Y-%m-%d"),
        latitude_deg,
        T
    );
    return 0;
}
