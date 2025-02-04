#!/usr/bin/env -S vala -X -lm -X -O2 -X -march=native --cc="ccache cc" -X -pipe -X -fuse-ld=mold

/**
 * Computes solar declination (in degrees) based on the day of the year.
 *
 * Formula: δ = 23.44° * sin(2π/365 * (n - 81))
 *
 * @param n The day number in the year.
 * @return Solar declination in degrees.
 */
double solar_declination (int n) {
    return 23.44 * Math.sin (2 * Math.PI / 365.0 * (n - 81));
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
double day_length (double latitude, DateTime date_obj) {
    double phi = latitude * Math.PI / 180.0; // Convert to radians
    int n = date_obj.get_day_of_year (); // nth day of the year
    double delta_deg = solar_declination (n);
    double delta = delta_deg * Math.PI / 180.0; // Convert to radians

    double X = - Math.tan (phi) * Math.tan (delta);
    if (X < -1) {
        return 24.0;
    } else if (X > 1) {
        return 0.0;
    } else {
        double omega0 = Math.acos (X);
        double omega0_deg = omega0 * 180.0 / Math.PI;
        double T = 2 * (omega0_deg / 15.0);
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
    double latitude = 0; 
    string? date_str = null;
    OptionEntry[] entries = {
        { "latitude", 'l', OptionFlags.NONE, OptionArg.DOUBLE, out latitude,
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

    double T = day_length (latitude, date_obj);
    stdout.printf (
        "%s  |  Latitude: %.2f deg  |  Daylight: %.2f hours\n",
        date_obj.format ("%Y-%m-%d"),
        latitude,
        T
    );
    return 0;
}
