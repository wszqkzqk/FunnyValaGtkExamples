#!/usr/bin/env -S vala --pkg=gtk4 -X -lm -X -O2 -X -march=native -X -pipe

/**
 * Solar Angle Calculator Application.
 *
 * A GTK4 application that calculates and visualizes solar elevation angles
 * throughout the day for a given location and date. The application provides
 * an interactive interface for setting latitude, longitude, timezone, and date,
 * and displays a real-time chart of solar elevation angles with export capabilities.
 */
public class SolarAngleApp : Gtk.Application {
    private const double DEG2RAD = Math.PI / 180.0;
    private const double RAD2DEG = 180.0 / Math.PI;
    private const int RESOLUTION_PER_MIN = 1440; // 1 sample per minute

    private Gtk.ApplicationWindow window;
    private Gtk.DrawingArea drawing_area;
    private Gtk.SpinButton latitude_spin;
    private Gtk.SpinButton longitude_spin;
    private Gtk.SpinButton timezone_spin;
    private Gtk.Calendar calendar;
    private Gtk.Button export_button;
    private double latitude = 0.0;
    private double longitude = 0.0;
    private double timezone_offset_hours = 0.0;
    private DateTime selected_date;
    private double sun_angles[RESOLUTION_PER_MIN];

    /**
     * Creates a new SolarAngleApp instance.
     *
     * Initializes the application with a unique application ID and sets
     * the selected date to the current local date.
     */
    public SolarAngleApp () {
        Object (application_id: "com.github.wszqkzqk.SolarAngleApp");
        selected_date = new DateTime.now_local ();
    }

    /**
     * Activates the application and creates the main window.
     *
     * Sets up the user interface including input controls, drawing area,
     * and initializes the plot data with current settings.
     */
    protected override void activate () {
        window = new Gtk.ApplicationWindow (this);
        window.title = "Solar Angle Calculator";
        window.default_width = 1000;
        window.default_height = 700;

        var main_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            margin_start = 10,
            margin_end = 10,
            margin_top = 10,
            margin_bottom = 10,
        };

        var left_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 15) {
            hexpand = false,
            margin_start = 10,
            margin_end = 10,
            margin_top = 10,
            margin_bottom = 10,
        };

        var location_time_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var location_time_label = new Gtk.Label ("<b>Location and Time Settings</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };
        location_time_group.append (location_time_label);

        var settings_grid = new Gtk.Grid () {
            column_spacing = 10,
            row_spacing = 8,
            margin_top = 5,
        };

        var latitude_label = new Gtk.Label ("Latitude (deg):") {
            halign = Gtk.Align.START,
        };
        latitude_spin = new Gtk.SpinButton.with_range (-90, 90, 0.1) {
            value = latitude,
            digits = 2,
        };
        latitude_spin.value_changed.connect (() => {
            latitude = latitude_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        var longitude_label = new Gtk.Label ("Longitude (deg):") {
            halign = Gtk.Align.START,
        };
        longitude_spin = new Gtk.SpinButton.with_range (-180.0, 180.0, 1.0) {
            value = longitude,
            digits = 1,
        };
        longitude_spin.value_changed.connect (() => {
            longitude = longitude_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        var timezone_label = new Gtk.Label ("Timezone (hour):") {
            halign = Gtk.Align.START,
        };
        timezone_spin = new Gtk.SpinButton.with_range (-12.0, 14.0, 0.5) {
            value = timezone_offset_hours,
            digits = 1,
        };
        timezone_spin.value_changed.connect (() => {
            timezone_offset_hours = timezone_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        settings_grid.attach (latitude_label, 0, 0, 1, 1);
        settings_grid.attach (latitude_spin, 1, 0, 1, 1);
        settings_grid.attach (longitude_label, 0, 1, 1, 1);
        settings_grid.attach (longitude_spin, 1, 1, 1, 1);
        settings_grid.attach (timezone_label, 0, 2, 1, 1);
        settings_grid.attach (timezone_spin, 1, 2, 1, 1);

        location_time_group.append (settings_grid);

        var date_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var date_label = new Gtk.Label ("<b>Date Selection</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };
        calendar = new Gtk.Calendar ();
        calendar.day_selected.connect (() => {
            selected_date = calendar.get_date ();
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        date_group.append (date_label);
        date_group.append (calendar);

        var export_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var export_label = new Gtk.Label ("<b>Export Chart</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };

        export_button = new Gtk.Button.with_label ("Export Image");
        export_button.clicked.connect (on_export_clicked);

        export_group.append (export_label);
        export_group.append (export_button);

        left_panel.append (location_time_group); // Changed from latitude_group
        left_panel.append (date_group);
        left_panel.append (export_group);

        drawing_area = new Gtk.DrawingArea () {
            hexpand = true,
            vexpand = true,
            width_request = 600,
            height_request = 500,
        };
        drawing_area.set_draw_func (draw_sun_angle_chart);

        main_box.append (left_panel);
        main_box.append (drawing_area);

        update_plot_data ();

        window.child = main_box;
        window.present ();
    }

    /**
     * Calculates solar elevation angles for each minute of the day.
     *
     * @param latitude_rad Latitude in radians.
     * @param day_of_year Day of the year (1-365/366).
     * @param year The year.
     * @param longitude_deg Longitude in degrees.
     * @param timezone_offset_hrs Timezone offset from UTC in hours.
     */
    private void generate_sun_angles (double latitude_rad, int day_of_year, int year, double longitude_deg, double timezone_offset_hrs) {
        double sin_lat = Math.sin (latitude_rad);
        double cos_lat = Math.cos (latitude_rad);

        double days_in_year = ((year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0))) ? 366.0 : 365.0;

        for (int i = 0; i < RESOLUTION_PER_MIN; i += 1) {
            // fractional_day_component: day of year plus fraction of the day
            double fractional_day_component = day_of_year - 1 + ((double) i) / RESOLUTION_PER_MIN;
            // gamma: fractional year angle in radians
            double gamma_rad = (2.0 * Math.PI / days_in_year) * fractional_day_component;

            // Solar declination delta (rad) via Fourier series approximation
            double decl_rad = 0.006918
                - 0.399912 * Math.cos (gamma_rad)
                + 0.070257 * Math.sin (gamma_rad)
                - 0.006758 * Math.cos (2.0 * gamma_rad)
                + 0.000907 * Math.sin (2.0 * gamma_rad)
                - 0.002697 * Math.cos (3.0 * gamma_rad)
                + 0.001480 * Math.sin (3.0 * gamma_rad);

            // Equation of Time (EoT) in minutes
            double eqtime_minutes = 229.18 * (0.000075
                + 0.001868 * Math.cos (gamma_rad)
                - 0.032077 * Math.sin (gamma_rad)
                - 0.014615 * Math.cos (2.0 * gamma_rad)
                - 0.040849 * Math.sin (2.0 * gamma_rad));

            // True Solar Time (TST) in minutes, correcting local clock by EoT and longitude
            double tst_minutes = i + eqtime_minutes + 4.0 * longitude_deg - 60.0 * timezone_offset_hrs;

            // Hour angle H (°) relative to solar noon
            double ha_deg = tst_minutes / 4.0 - 180.0;
            double ha_rad = ha_deg * DEG2RAD;

            // cos(phi): cosine of zenith angle via spherical trig
            double cos_phi = sin_lat * Math.sin (decl_rad) + cos_lat * Math.cos (decl_rad) * Math.cos(ha_rad);
            // clamp to valid range
            if (cos_phi > 1.0) cos_phi = 1.0;
            if (cos_phi < -1.0) cos_phi = -1.0;
            // Zenith angle phi (rad)
            double phi_rad = Math.acos (cos_phi);

            // Solar elevation alpha = 90° - phi, convert to degrees
            double solar_elevation_rad = Math.PI / 2.0 - phi_rad;
            sun_angles[i] = solar_elevation_rad * RAD2DEG;
        }
    }

    /**
     * Updates solar angle data for current settings.
     */
    private void update_plot_data () {
        int day_of_year = selected_date.get_day_of_year ();
        double latitude_rad = latitude * DEG2RAD;
        int year = selected_date.get_year ();
        generate_sun_angles (latitude_rad, day_of_year, year, longitude, timezone_offset_hours);
    }

    /**
     * Draws the solar elevation chart.
     */
    private void draw_sun_angle_chart (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        // Fill background
        cr.set_source_rgb (1, 1, 1);
        cr.paint ();

        int ml = 70, mr = 20, mt = 50, mb = 70;
        int pw = width - ml - mr, ph = height - mt - mb;

        double y_min = -90, y_max = 90;

        double horizon_y = mt + ph * (1 - (0 - y_min) / (y_max - y_min));
        
        // Shade area below horizon
        cr.set_source_rgba (0.7, 0.7, 0.7, 0.3);
        cr.rectangle (ml, horizon_y, pw, height - mb - horizon_y);
        cr.fill ();

        // Draw horizontal grid every 15°
        cr.set_source_rgba (0.5, 0.5, 0.5, 0.5);
        cr.set_line_width (1);
        for (int a = -90; a <= 90; a += 15) {
            double yv = mt + ph * (1 - (a - y_min) / (y_max - y_min));
            cr.move_to (ml, yv);
            cr.line_to (width - mr, yv);
            cr.stroke ();
        }
        // Draw vertical grid every 2 hours
        for (int h = 0; h <= 24; h += 2) {
            double xv = ml + pw * (h / 24.0);
            cr.move_to (xv, mt);
            cr.line_to (xv, height - mb);
            cr.stroke ();
        }

        // Draw axes and horizon
        cr.set_source_rgb (0, 0, 0);
        cr.set_line_width (2);
        cr.move_to (ml, height - mb);
        cr.line_to (width - mr, height - mb);
        cr.stroke ();
        cr.move_to (ml, mt);
        cr.line_to (ml, height - mb);
        cr.stroke ();
        // Horizon line
        cr.move_to (ml, horizon_y);
        cr.line_to (width - mr, horizon_y);
        cr.stroke ();

        // Draw axis ticks and labels
        cr.set_line_width (1);
        cr.set_font_size (20);
        for (int a = -90; a <= 90; a += 15) {
            double yv = mt + ph * (1 - (a - y_min) / (y_max - y_min));
            cr.move_to (ml - 5, yv);
            cr.line_to (ml, yv);
            cr.stroke ();
            var te = Cairo.TextExtents ();
            var txt = a.to_string ();
            cr.text_extents (txt, out te);
            cr.move_to (ml - 10 - te.width, yv + te.height / 2);
            cr.show_text (txt);
        }
        for (int h = 0; h <= 24; h += 2) {
            double xv = ml + pw * (h / 24.0);
            cr.move_to (xv, height - mb);
            cr.line_to (xv, height - mb + 5);
            cr.stroke ();
            var te = Cairo.TextExtents ();
            var txt = h.to_string ();
            cr.text_extents (txt, out te);
            cr.move_to (xv - te.width / 2, height - mb + 25);
            cr.show_text (txt);
        }

        // Plot solar elevation curve
        cr.set_source_rgb (1, 0, 0);
        cr.set_line_width (2);
        for (int i = 0; i < RESOLUTION_PER_MIN; i += 1) {
            double x = ml + pw * (i / (double)(RESOLUTION_PER_MIN - 1));
            double y = mt + ph * (1 - (sun_angles[i] - y_min) / (y_max - y_min));
            if (i == 0) {
                cr.move_to (x, y);
            } else {
                cr.line_to (x, y);
            }
        }
        cr.stroke ();

        // Draw axis titles
        cr.set_source_rgb (0, 0, 0);
        cr.set_font_size (20);
        string x_title = "Time (Hour)";
        Cairo.TextExtents x_ext;
        cr.text_extents (x_title, out x_ext);
        cr.move_to ((double) width / 2 - x_ext.width / 2, height - mb + 55);
        cr.show_text (x_title);
        string y_title = "Solar Elevation (°)";
        Cairo.TextExtents y_ext;
        cr.text_extents (y_title, out y_ext);
        cr.save ();
        cr.translate (ml - 45, (double)height / 2);
        cr.rotate (-Math.PI / 2);
        cr.move_to (-y_ext.width / 2, 0);
        cr.show_text (y_title);
        cr.restore ();

        // Draw chart captions
        string caption_line1 = "Solar Elevation Angle - Date: %s".printf(selected_date.format("%Y-%m-%d"));
        string caption_line2 = "Lat: %.2f°, Lon: %.1f°, TZ: UTC%+.1f".printf(latitude, longitude, timezone_offset_hours);
        
        cr.set_font_size(18);
        Cairo.TextExtents cap_ext1, cap_ext2;
        cr.text_extents(caption_line1, out cap_ext1);
        cr.text_extents(caption_line2, out cap_ext2);

        double total_caption_height = cap_ext1.height + cap_ext2.height + 5;

        cr.move_to((width - cap_ext1.width) / 2, (mt - total_caption_height) / 2 + cap_ext1.height);
        cr.show_text(caption_line1);
        cr.move_to((width - cap_ext2.width) / 2, (mt - total_caption_height) / 2 + cap_ext1.height + 5 + cap_ext2.height);
        cr.show_text(caption_line2);
    }

    /**
     * Handles export button click event.
     *
     * Shows a file save dialog with filters for PNG, SVG, and PDF formats.
     */
    private void on_export_clicked () {
        // Show save dialog with PNG, SVG, PDF filters
        var png_filter = new Gtk.FileFilter ();
        png_filter.name = "PNG Images";
        png_filter.add_mime_type ("image/png");
        
        var svg_filter = new Gtk.FileFilter ();
        svg_filter.name = "SVG Images";
        svg_filter.add_mime_type ("image/svg+xml");

        var pdf_filter = new Gtk.FileFilter ();
        pdf_filter.name = "PDF Documents";
        pdf_filter.add_mime_type ("application/pdf");

        var filter_list = new ListStore (typeof (Gtk.FileFilter));
        filter_list.append (png_filter);
        filter_list.append (svg_filter);
        filter_list.append (pdf_filter);

        var file_dialog = new Gtk.FileDialog () {
            modal = true,
            initial_name = "solar_elevation_chart.png",
            filters = filter_list
        };

        file_dialog.save.begin (window, null, (obj, res) => {
            try {
                var file = file_dialog.save.end (res);
                if (file != null) {
                    string filepath = file.get_path ();
                    export_chart (filepath);
                }
            } catch (Error e) {
                message ("File has not been saved: %s", e.message);
            }
        });
    }

    /**
     * Exports the current chart to a file.
     *
     * Supports PNG, SVG, and PDF formats based on file extension.
     * Defaults to PNG if extension is not recognized.
     *
     * @param filepath The file path where the chart should be saved.
     */
    private void export_chart (string filepath) {
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
            draw_sun_angle_chart (drawing_area, cr, width, height);
        } else if (extension == ".pdf") {
            Cairo.PdfSurface surface = new Cairo.PdfSurface (filepath, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_sun_angle_chart (drawing_area, cr, width, height);
        } else {
            Cairo.ImageSurface surface = new Cairo.ImageSurface (Cairo.Format.RGB24, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_sun_angle_chart (drawing_area, cr, width, height);
            surface.write_to_png (filepath);
        }
    }

    /**
     * Application entry point.
     *
     * Creates and runs the SolarAngleApp instance.
     *
     * @param args Command line arguments.
     * @return Exit code.
     */
    public static int main (string[] args) {
        var app = new SolarAngleApp ();
        return app.run (args);
    }
}
