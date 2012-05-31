

public class WindowSwitcher : Clutter.Group {
    
    int ICON_SIZE = 128;
    int spacing   = 12;
    
    public float len;
    
    Clutter.CairoTexture bg;
    Clutter.CairoTexture cur;
    Clutter.Text         title;
    
    int _windows = 1;
    public int windows {
        get { return _windows; }
        set {
            _windows = value;
            this.width = spacing+_windows*(ICON_SIZE+spacing);
        }
    }
    
    GLib.List<weak Meta.Window> window_list;
    
    Meta.Window? _current_window;
    Meta.Window? current_window {
        get { return _current_window; }
        set {
            _current_window = value;
            
            this.title.text = this.current_window.title;
            this.title.x = (int)(this.width/2-this.title.width/2);
        }
    }
    
    Gala.Plugin plugin;
    
    public WindowSwitcher (Gala.Plugin plugin) {
        this.plugin = plugin;
        
        this.height = ICON_SIZE+spacing*2;
        this.opacity = 0;
        this.scale_gravity = Clutter.Gravity.CENTER;
        
        this.bg = new Clutter.CairoTexture (100, 100);
        this.bg.auto_resize = true;
        
        this.bg.draw.connect ( (ctx) => {
            Granite.Drawing.Utilities.cairo_rounded_rectangle (ctx, 0.5, 0.5, width-1, 
                height-1, 10);
            ctx.set_line_width (1);
            ctx.set_source_rgba (0, 0, 0, 0.5);
            ctx.stroke_preserve ();
            ctx.set_source_rgba (1, 1, 1, 0.4);
            ctx.fill ();
            
            return true;
        });
        
        this.cur = new Clutter.CairoTexture (ICON_SIZE, ICON_SIZE);
        this.cur.width = ICON_SIZE;
        this.cur.height = ICON_SIZE;
        this.cur.y = spacing+1;
        this.cur.x = spacing+1;
        this.cur.auto_resize = true;
        this.cur.draw.connect ( (ctx) => {
            Granite.Drawing.Utilities.cairo_rounded_rectangle (ctx, 0.5, 0.5, cur.width-2, 
                cur.height-1, 10);
            ctx.set_line_width (1);
            ctx.set_source_rgba (0, 0, 0, 0.9);
            ctx.stroke_preserve ();
            ctx.set_source_rgba (1, 1, 1, 0.9);
            ctx.fill ();
            
            return true;
        });
        this.windows = 1;
        
        this.title = new Clutter.Text.with_text ("bold 16px", "");
        this.title.y = ICON_SIZE + spacing*2 + 6;
        this.title.color = {255, 255, 255, 255};
        this.title.add_effect (new TextShadowEffect (1, 1, 220));
        
        this.add_child (bg);
        this.add_child (cur);
        this.add_child (title);
        bg.add_constraint (new Clutter.BindConstraint (this, Clutter.BindCoordinate.WIDTH, 0));
        bg.add_constraint (new Clutter.BindConstraint (this, Clutter.BindCoordinate.HEIGHT, 0));
        
        this.key_release_event.connect_after ( (e) => {
            if (((e.modifier_state & Clutter.ModifierType.MOD1_MASK) == 0) || 
                e.keyval == Clutter.Key.Alt_L) {
                plugin.end_modal ();
                current_window.activate (e.time);
                
                this.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 200, opacity:0);
            }
            return true;
        });
        this.captured_event.connect ( (e) => {
            if (!(e.get_type () == Clutter.EventType.KEY_PRESS))
                return false;
            
            bool backward = (((Clutter.Event)e).get_state () & X.KeyMask.ShiftMask) == 1;
            var action = plugin.get_screen ().get_display ().get_keybinding_action (
                ((Clutter.Event)e).get_key_code (), ((Clutter.Event)e).get_state ());
            
            switch (action) {
                case Meta.KeyBindingAction.SWITCH_GROUP:
                case Meta.KeyBindingAction.SWITCH_WINDOWS:
                    this.current_window = plugin.get_screen ().get_display ().
                        get_tab_next (Meta.TabList.NORMAL, plugin.get_screen (), 
                        plugin.get_screen ().get_active_workspace (), this.current_window, backward);
                    break;
                case Meta.KeyBindingAction.SWITCH_GROUP_BACKWARD:
                case Meta.KeyBindingAction.SWITCH_WINDOWS_BACKWARD:
                    this.current_window = plugin.get_screen ().get_display ().
                        get_tab_next (Meta.TabList.NORMAL, plugin.get_screen (), 
                        plugin.get_screen ().get_active_workspace (), this.current_window, true);
                    break;
                default:
                    break;
            }
            cur.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 200, 
                x:0.0f+spacing+this.window_list.index (this.current_window)*(spacing+ICON_SIZE));
            return true;
        });
    }
    
    public void list_windows (Meta.Display display, Meta.Screen screen, 
        Meta.KeyBinding binding, bool backward) {
        this.get_children ().foreach ( (c) => { //clear
            if (c != cur && c != bg && c != title)
                this.remove_child (c);
        });
        
        this.current_window = display.get_tab_next (Meta.TabList.NORMAL, screen, 
            screen.get_active_workspace (), null, backward);
        if (this.current_window == null)
            this.current_window = display.get_tab_current (Meta.TabList.NORMAL, screen,
                screen.get_active_workspace ());
        if (this.current_window == null)
            return;
        
        if (binding.get_mask () == 0) {
            this.current_window.activate (display.get_current_time ());
            return;
        }
        
        var matcher = Bamf.Matcher.get_default ();
        
        var i = 0;
        this.window_list = screen.get_display ().get_tab_list (Meta.TabList.NORMAL, screen, 
            screen.get_active_workspace ()).copy ();
        this.window_list.foreach ( (w) => {
            if (w == null)
                return;
            
            Bamf.Window bamfwin = null;
            matcher.get_windows ().foreach ( (bamfw) => {
                if ((bamfw as Bamf.Window).get_pid () == (uint32)w.get_pid ()) {
                    bamfwin = bamfw as Bamf.Window;
                }
            });
            
            Gdk.Pixbuf image = null;
            if (bamfwin != null) {
                var app = matcher.get_application_for_window (bamfwin);
                if (app != null) {
                    var desktop = new GLib.DesktopAppInfo.from_filename (app.get_desktop_file ());
                    try {
                        image = Gtk.IconTheme.get_default ().lookup_by_gicon (desktop.get_icon (), 
                            ICON_SIZE, 0).load_icon ();
                    } catch (Error e) { warning (e.message); }
                }
            }
            
            if (image == null) {
                try {
                    image = Gtk.IconTheme.get_default ().load_icon ("application-default-icon", 
                        ICON_SIZE, 0);
                } catch (Error e) { warning (e.message); }
            }
            
            var icon = new GtkClutter.Texture ();
            try {
                icon.set_from_pixbuf (image);
            } catch (Error e) { warning (e.message); }
            
            icon.width = ICON_SIZE-10;
            icon.height = ICON_SIZE-10;
            icon.x = spacing+i*(spacing+ICON_SIZE)+5;
            icon.y = spacing+5;
            this.add_child (icon);
            
            i ++;
        });
        this.windows = i;
        
        var idx = this.window_list.index (this.current_window);
        cur.x = spacing+idx*(spacing+ICON_SIZE);
    }
}
