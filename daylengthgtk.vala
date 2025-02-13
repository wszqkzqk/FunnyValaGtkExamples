#!/usr/bin/env -S vala --pkg=gtk4 -X -lm -X -pipe -X -O2 -X -march=native

// Helper functions to compute day-of-year, solar declination and day length

/**
 * Returns the number of days in a given year.
 *
 * @param year The year to calculate the number of days.
 * @return Total number of days in the year.
 */
private inline int days_in_year (int year) {
    // Leap year: divisible by 400 or divisible by 4 but not by 100.
    if ((year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0))) {
        return 366;
    }
    return 365;
}

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
 * Calculates the day length (in hours) for a given latitude (in radians) and day number.
 *
 * Using formula: T = (24/π) * arccos( -tan(φ) * tan(δ) )
 *
 * φ: observer's latitude, δ: solar declination
 *
 * When |tan φ * tan δ| > 1, returns polar day (24 hours) or polar night (0 hours)
 *
 * @param latitude_rad Latitude in radians.
 * @param n The day number in the year.
 * @return Day length in hours.
 */
private inline double compute_day_length (double latitude_rad, int n) {
    double phi = latitude_rad;
    double delta = solar_declination (n);
    double X = -Math.tan (phi) * Math.tan (delta);
    if (X < -1) {
        return 24.0; // Polar day
    } else if (X > 1) {
        return 0.0;  // Polar night
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
 * Generates an array of day lengths for all days at the given latitude (in radians) and year.
 *
 * @param latitude_rad Latitude in radians.
 * @param year The year for which to generate day lengths.
 * @return Array of day lengths in hours.
 */
private inline double[] generate_day_lengths (double latitude_rad, int year) {
    int total_days = days_in_year (year);
    double[] lengths = new double[total_days];
    for (int i = 0; i < total_days; i += 1) {
        lengths[i] = compute_day_length (latitude_rad, i + 1);
    }
    return lengths;
}

/**
 * Window for displaying the day length plot.
 */
public class DayLengthWindow : Gtk.ApplicationWindow {
    private Gtk.Entry latitude_entry;
    private Gtk.Entry year_entry;
    private Gtk.DrawingArea drawing_area;
    private double[] day_lengths;
    private int current_year;
    private double latitude_deg;
    private Gtk.Button export_button;

    /**
     * Constructs a new DayLengthWindow.
     *
     * @param app The Gtk.Application instance.
     */
    public DayLengthWindow (Gtk.Application app) {
        Object (
            application: app,
            title: "Day Length Plotter",
            default_width: 800,
            default_height: 600
        );

        // Initialize current_year first
        DateTime now = new DateTime.now_local ();
        current_year = now.get_year ();

        // Use vertical box as the main container
        var vbox_main = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
        this.child = vbox_main;

        // Input area (using horizontal Box layout)
        var hbox_controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
        vbox_main.append (hbox_controls);

        var lat_label = new Gtk.Label ("<b>Latitude (degrees):</b>") {
            margin_start = 5,
            margin_top = 5,
            halign = Gtk.Align.START,
            use_markup = true
        };
        hbox_controls.append (lat_label);

        latitude_entry = new Gtk.Entry () {
            width_chars = 10
        };
        hbox_controls.append (latitude_entry);

        var year_label = new Gtk.Label ("<b>Year:</b>") {
            margin_start = 5,
            margin_top = 5,
            halign = Gtk.Align.START,
            use_markup = true
        };
        hbox_controls.append (year_label);

        year_entry = new Gtk.Entry () {
            width_chars = 10,
            // Set year entry text using current_year
            text = current_year.to_string ()
        };
        hbox_controls.append (year_entry);

        var plot_button = new Gtk.Button.with_label ("Plot");
        hbox_controls.append (plot_button);
        plot_button.clicked.connect (() => {
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        // Export image button
        export_button = new Gtk.Button.with_label ("Export");
        hbox_controls.append (export_button);
        export_button.clicked.connect (() => {
            var png_filter = new Gtk.FileFilter ();
            png_filter.name = "PNG Images";
            png_filter.add_mime_type ("image/png");
            
            var svg_filter = new Gtk.FileFilter ();
            svg_filter.name = "SVG Images";
            svg_filter.add_mime_type ("image/svg+xml");

            var pdf_filter = new Gtk.FileFilter ();
            pdf_filter.name = "PDF Documents";
            pdf_filter.add_mime_type ("application/pdf");

            // FileDialog.filters are required to contain default filter and others
            var filter_list = new ListStore (typeof (Gtk.FileFilter));
            filter_list.append (png_filter);
            filter_list.append (svg_filter);
            filter_list.append (pdf_filter);

            var file_dialog = new Gtk.FileDialog () {
                modal = true,
                initial_name = "daylength_plot.png",
                filters = filter_list
            };

            file_dialog.save.begin (this, null, (obj, res) => {
                try {
                    var file = file_dialog.save.end (res);
                    if (file != null) {
                        string filepath = file.get_path ();
                        export_plot (filepath);
                    }
                } catch (Error e) {
                    // Usually due to the user canceling the dialog
                    message ("File has not been saved: %s", e.message);
                }
            });
        });

        // Drawing area: using Gtk.DrawingArea and Cairo for plotting
        drawing_area = new Gtk.DrawingArea () {
            hexpand = true,
            vexpand = true
        };
        // Register drawing callback
        drawing_area.set_draw_func (this.draw_plot);
        vbox_main.append (drawing_area);
    }

    /**
     * Updates plot data based on input values.
     */
    private void update_plot_data () {
        latitude_deg = double.parse (latitude_entry.text);
        current_year = int.parse (year_entry.text);
        // Convert input latitude (in degrees) to radians
        double latitude_rad = latitude_deg * Math.PI / 180.0;
        day_lengths = generate_day_lengths (latitude_rad, current_year);
    }

    /**
     * Drawing callback to render the day length plot.
     *
     * @param area The drawing area widget.
     * @param cr The Cairo context.
     * @param width The width of the drawing area.
     * @param height The height of the drawing area.
     */
    private void draw_plot (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        // Clear background to white
        cr.set_source_rgb (1, 1, 1);
        cr.paint ();

        // Set margins
        int margin_left = 75;
        int margin_right = 20;
        int margin_top = 50;
        int margin_bottom = 70;
        int plot_width = width - margin_left - margin_right;
        int plot_height = height - margin_top - margin_bottom;

        // Fixed Y axis range: -0.5 to 24.5
        double y_min = -0.5, y_max = 24.5;
        // X axis range: 1 to total_days
        int total_days = (day_lengths != null) ? day_lengths.length : 365;

        // Draw grid lines (gray)
        cr.set_source_rgba (0.5, 0.5, 0.5, 0.5);
        cr.set_line_width (1.0);
        // Horizontal grid lines (every 3 hours)
        for (int tick = 0; tick <= 24; tick += 3) {
            double y_val = margin_top + (plot_height * (1 - (tick - y_min) / (y_max - y_min)));
            cr.move_to (margin_left, y_val);
            cr.line_to (width - margin_right, y_val);
            cr.stroke ();
        }
        // Vertical grid lines (start of each month)
        for (int month = 1; month <= 12; month += 1) {
            DateTime month_start = new DateTime (new TimeZone.local (), current_year, month, 1, 0, 0, 0);
            int day_num = month_start.get_day_of_year ();
            double x_pos = margin_left + (plot_width * ((double) (day_num - 1) / (total_days - 1)));
            cr.move_to (x_pos, margin_top);
            cr.line_to (x_pos, height - margin_bottom);
            cr.stroke ();
        }

        // Draw axes (black, bold)
        cr.set_source_rgb (0, 0, 0);
        cr.set_line_width (2.0);
        // X axis
        cr.move_to (margin_left, height - margin_bottom);
        cr.line_to (width - margin_right, height - margin_bottom);
        cr.stroke ();
        // Y axis
        cr.move_to (margin_left, margin_top);
        cr.line_to (margin_left, height - margin_bottom);
        cr.stroke ();

        // Draw Y axis ticks
        cr.set_line_width (1.0);
        for (int tick = 0; tick <= 24; tick += 3) {
            double y_val = margin_top + (plot_height * (1 - (tick - y_min) / (y_max - y_min)));
            cr.move_to (margin_left - 5, y_val);
            cr.line_to (margin_left, y_val);
            cr.stroke ();
            // Draw tick labels
            cr.set_font_size (22);
            Cairo.TextExtents ext;
            cr.text_extents (tick.to_string (), out ext);
            cr.move_to (margin_left - 10 - ext.width, y_val + ext.height / 2);
            cr.show_text (tick.to_string ());
        }

        // Draw X axis ticks (start of each month)
        for (int month = 1; month <= 12; month += 1) {
            // Use GLib.DateTime to construct the 1st of each month
            DateTime month_start = new DateTime (new TimeZone.local (), current_year, month, 1, 0, 0, 0);
            int day_num = month_start.get_day_of_year ();
            double x_pos = margin_left + (plot_width * ((double) (day_num - 1) / (total_days - 1)));
            cr.move_to (x_pos, height - margin_bottom);
            cr.line_to (x_pos, height - margin_bottom + 5);
            cr.stroke ();
            // Draw month labels
            string label = month.to_string ();
            cr.set_font_size (22);
            Cairo.TextExtents ext;
            cr.text_extents (label, out ext);
            cr.move_to (x_pos - ext.width / 2, height - margin_bottom + 20);
            cr.show_text (label);
        }

        // Draw X and Y axis titles
        cr.set_source_rgb (0, 0, 0);
        cr.set_font_size (22);
        
        // X axis title
        string x_title = "Date (Month)";
        Cairo.TextExtents x_ext;
        cr.text_extents (x_title, out x_ext);
        cr.move_to ((double) width / 2 - x_ext.width / 2, height - margin_bottom + 50);
        cr.show_text (x_title);
        
        // Y axis title
        string y_title = "Day Length (hours)";
        Cairo.TextExtents y_ext;
        cr.text_extents (y_title, out y_ext);
        cr.save ();
        // Position 45 pixels to the left of Y axis, vertically centered
        cr.translate (margin_left - 45, (double) height / 2);
        // Rotate -90 degrees (π/2) for vertical text
        cr.rotate (-Math.PI / 2);
        // Adjust text position for vertical centering
        cr.move_to (-y_ext.width / 2, 0);
        cr.show_text (y_title);
        cr.restore ();

        // Add caption below the X axis title for clarity and aesthetics
        string caption;
        if (latitude_entry.text == "" || year_entry.text == "") {
            caption = "Day Length";
        } else {
            caption = "Day Length - Latitude: " + latitude_entry.text + "°, Year: " + year_entry.text;
        }
        cr.set_font_size (22);
        Cairo.TextExtents cap_ext;
        cr.text_extents (caption, out cap_ext);
        cr.move_to ((width - cap_ext.width) / 2, (double) margin_top / 2);
        cr.show_text (caption);

        // Return if no data
        if (day_lengths == null) {
            return;
        }

        // Draw data curve (red, bold)
        cr.set_source_rgb (1, 0, 0);
        cr.set_line_width (2.5);
        for (int i = 0; i < total_days; i += 1) {
            double x = margin_left + (plot_width * ((double) i / (total_days - 1)));
            double y = margin_top + (plot_height * (1 - (day_lengths[i] - y_min) / (y_max - y_min)));
            if (i == 0) {
                cr.move_to (x, y);
            } else {
                cr.line_to (x, y);
            }
        }
        cr.stroke ();
    }

    /**
     * Exports the current day length plot to an image file (PNG or SVG).
     *
     * This function gets the current width and height of the drawing area.
     * If invalid, it defaults to 800x600.
     * It then creates a Cairo surface (SVG or PNG) and draws the plot onto it.
     *
     * @param filepath The destination file path.
     */
    private void export_plot (string filepath) {
        int width = drawing_area.get_width ();
        int height = drawing_area.get_height ();

        if (width <= 0 || height <= 0) {
            width = 800;
            height = 600;
        }

        string? extension = null;
        var last_dot = filepath.last_index_of_char ('.');
        if (last_dot != -1) {
            extension = filepath[last_dot:].down ();
        }

        if (extension == ".svg") {
            Cairo.SvgSurface surface = new Cairo.SvgSurface (filepath, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_plot (drawing_area, cr, width, height);
        } else if (extension == ".pdf") {
            Cairo.PdfSurface surface = new Cairo.PdfSurface (filepath, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_plot (drawing_area, cr, width, height);
        } else {
            Cairo.ImageSurface surface = new Cairo.ImageSurface (Cairo.Format.RGB24, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_plot (drawing_area, cr, width, height);
            surface.write_to_png (filepath);
        }
    }
}

/**
 * Main application class for Day Length Plotter.
 */
public class DayLengthApp : Gtk.Application {

    /**
     * Constructs a new DayLengthApp.
     */
    public DayLengthApp () {
        Object (
            application_id: "com.github.wszqkzqk.DayLengthApp",
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    /**
     * Activates the application.
     */
    protected override void activate () {
        var win = new DayLengthWindow (this);
        win.present ();
    }
}

/**
 * Main entry point.
 *
 * @param args Command line arguments.
 * @return Exit status code.
 */
public static int main (string[] args) {
    var app = new DayLengthApp ();
    return app.run (args);
}
