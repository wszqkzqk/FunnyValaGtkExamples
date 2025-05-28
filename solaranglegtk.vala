#!/usr/bin/env -S vala --pkg=gtk4 -X -lm -X -O2 -X -march=native -X -pipe

public class SolarAngleApp : Gtk.Application {
    private const double DEG2RAD = Math.PI / 180.0; // degrees to radians
    private const double RAD2DEG = 180.0 / Math.PI; // radians to degrees
    private const double AXIAL_TILT = 23.44 * DEG2RAD; // Earth's tilt in radians
    private const double DAY_FACTOR = 2.0 * Math.PI / 365.0; // orbital angle change per day
    private const int RESOLUTION = 1440; // samples per 24h
    private const int SPRING_EQUINOX_OFFSET = 79; // spring equinox's offset in days

    private Gtk.ApplicationWindow window;
    private Gtk.DrawingArea drawing_area;
    private Gtk.SpinButton latitude_spin;
    private Gtk.Calendar calendar;
    private Gtk.Button export_button;
    private double latitude = 0.0;
    private DateTime selected_date;
    private double sun_angles[RESOLUTION]; // Fixed size array for solar angles

    public SolarAngleApp () {
        Object (application_id: "com.github.wszqkzqk.SolarAngleApp");
        selected_date = new DateTime.now_local ();
    }

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
            width_request = 320,
            hexpand = false,
            margin_start = 10,
            margin_end = 10,
            margin_top = 10,
            margin_bottom = 10,
        };

        var latitude_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var latitude_label = new Gtk.Label ("<b>Latitude Settings</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };

        var latitude_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
        var latitude_input_label = new Gtk.Label ("Latitude (deg):");
        latitude_input_label.halign = Gtk.Align.START;
        latitude_spin = new Gtk.SpinButton.with_range (-90, 90, 0.1) {
            value = latitude,
            digits = 2,
            width_request = 100,
        };
        latitude_spin.value_changed.connect (() => {
            latitude = latitude_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        latitude_box.append (latitude_input_label);
        latitude_box.append (latitude_spin);
        latitude_group.append (latitude_label);
        latitude_group.append (latitude_box);

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

        left_panel.append (latitude_group);
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

    private void generate_sun_angles (double latitude_rad, int day_of_year) {
        // Compute solar elevation angles for each time sample
        double sin_lat = Math.sin (latitude_rad);
        double cos_lat = Math.cos (latitude_rad);
        // solar declination relative to vernal equinox
        double delta = AXIAL_TILT * Math.sin (DAY_FACTOR * (day_of_year - SPRING_EQUINOX_OFFSET));
        for (int i = 0; i < RESOLUTION; i += 1) {
            // map index to hour of day, then to hour angle around solar noon
            double t = 24.0 / (RESOLUTION - 1) * i;
            double hour_angle = (2.0 * Math.PI / 24.0) * (t - 12.0);
            // spherical formula for elevation angle
            double sin_a = sin_lat * Math.sin (delta) + cos_lat * Math.cos (delta) * Math.cos (hour_angle);
            sun_angles[i] = Math.asin (sin_a) * RAD2DEG;
        }
    }

    private void update_plot_data () {
        int day_of_year = selected_date.get_day_of_year ();
        double latitude_rad = latitude * DEG2RAD;
        generate_sun_angles (latitude_rad, day_of_year);
    }

    private void draw_sun_angle_chart (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        // fill white background
        cr.set_source_rgb (1, 1, 1);
        cr.paint ();

        int ml = 70, mr = 20, mt = 50, mb = 70;
        int pw = width - ml - mr, ph = height - mt - mb;

        double y_min = -90, y_max = 90;

        double horizon_y = mt + ph * (1 - (0 - y_min) / (y_max - y_min));
        
        cr.set_source_rgba (0.7, 0.7, 0.7, 0.3);
        cr.rectangle (ml, horizon_y, pw, height - mb - horizon_y);
        cr.fill ();

        // draw horizontal grid every 15° elevation
        cr.set_source_rgba (0.5, 0.5, 0.5, 0.5);
        cr.set_line_width (1);
        for (int a = -90; a <= 90; a += 15) {
            double yv = mt + ph * (1 - (a - y_min) / (y_max - y_min));
            cr.move_to (ml, yv);
            cr.line_to (width - mr, yv);
            cr.stroke ();
        }
        // draw vertical grid every 2 hours
        for (int h = 0; h <= 24; h += 2) {
            double xv = ml + pw * (h / 24.0);
            cr.move_to (xv, mt);
            cr.line_to (xv, height - mb);
            cr.stroke ();
        }

        // draw axes and horizon line
        cr.set_source_rgb (0, 0, 0);
        cr.set_line_width (2);
        cr.move_to (ml, height - mb);
        cr.line_to (width - mr, height - mb);
        cr.stroke ();
        cr.move_to (ml, mt);
        cr.line_to (ml, height - mb);
        cr.stroke ();
        // Draw horizon line
        cr.move_to (ml, horizon_y);
        cr.line_to (width - mr, horizon_y);
        cr.stroke ();

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

        // plot solar elevation curve in red
        cr.set_source_rgb (1, 0, 0);
        cr.set_line_width (2);
        for (int i = 0; i < RESOLUTION; i += 1) {
            double x = ml + pw * (i / (double)(RESOLUTION - 1));
            double y = mt + ph * (1 - (sun_angles[i] - y_min) / (y_max - y_min));
            if (i == 0) {
                cr.move_to (x, y);
            } else {
                cr.line_to (x, y);
            }
        }
        cr.stroke ();

        cr.set_source_rgb (0, 0, 0);
        cr.set_font_size (20);
        string x_title = "Time (Hour)";
        Cairo.TextExtents x_ext;
        cr.text_extents (x_title, out x_ext);
        cr.move_to ((double)width / 2 - x_ext.width / 2, height - mb + 55);
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

        string caption = "Solar Elevation Angle - Latitude: %.2f°, Date: %s".printf (
            latitude, selected_date.format ("%Y-%m-%d"));
        cr.set_font_size (22);
        Cairo.TextExtents cap_ext;
        cr.text_extents (caption, out cap_ext);
        cr.move_to ((width - cap_ext.width) / 2, (double)mt / 2);
        cr.show_text (caption);
    }

    private void on_export_clicked () {
        // Open save dialog with PNG, SVG & PDF filters
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

    private void export_chart (string filepath) {
        // Export current chart to chosen format by extension
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

    public static int main (string[] args) {
        var app = new SolarAngleApp ();
        return app.run (args);
    }
}
