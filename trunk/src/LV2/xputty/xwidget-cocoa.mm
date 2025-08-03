#ifdef __APPLE__
/*
 *=================================================================================*
 *=================           Copyright by ProBo 2025             =================*
 *================= Cocoa Implementation For Guitarix LV2 Plugins =================*
 *=================================================================================*
 */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <cairo.h>
#import <cairo-quartz.h>

extern "C" {

#include "xwidget.h"
#include "xwidget_private.h"

//Private Funckions needed for Cocoa
@interface XWidgetView : NSView {
@public
    Widget_t *widget;
    NSTrackingArea *trackingArea;
    
}
@end

@implementation XWidgetView

- (BOOL)isFlipped { return YES; }

- (instancetype)initWithWidget:(Widget_t *)w frame:(NSRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        widget = w;
        [self setWantsLayer:YES];
        NSTrackingArea *tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                                options:(NSTrackingMouseEnteredAndExited |
                                                                         NSTrackingMouseMoved |
                                                                         NSTrackingActiveAlways |
                                                                         NSTrackingInVisibleRect)
                                                                  owner:self
                                                               userInfo:nil];
        [self addTrackingArea:tracking];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    if (self->trackingArea) {
        [self removeTrackingArea:self->trackingArea];
        self->trackingArea = nil;
    }

    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect;

    self->trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                      options:options
                                                        owner:self
                                                     userInfo:nil];
    [self addTrackingArea:self->trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!widget) return;
    if (!widget || !widget->surface) {
        NSLog(@"drawRect called, but surface is NULL");
        return;
    }
    transparent_draw(widget, NULL);

    CGContextRef cgContext = [[NSGraphicsContext currentContext] CGContext];
    NSRect bounds = [self bounds];

    cairo_surface_t *surface = cairo_quartz_surface_create_for_cg_context(
        cgContext, bounds.size.width, bounds.size.height);
    cairo_t *cr = cairo_create(surface);
    cairo_set_source_surface(cr, widget->surface, 0, 0);
    cairo_paint(cr);
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

//Mouse Events
- (void)mouseDown:(NSEvent *)event {
    if (widget->state == 4) return;
    if (!widget) return;

    XButtonEvent xbutton;
    xbutton.window = (__bridge Window)self;
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    xbutton.x = loc.x;
    xbutton.y = loc.y;
    xbutton.button = Button1;

    widget->pos_x = loc.x;
    widget->pos_y = loc.y;

    if (widget->flags & HAS_TOOLTIP) hide_tooltip(widget);
    _button_press(widget, &xbutton, NULL);
    
}

- (void)mouseUp:(NSEvent *)event {
   if (widget->state == 4) return;
   if (!widget) return;

    XButtonEvent xbutton;
    xbutton.window = (__bridge Window)self;
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    xbutton.x = loc.x;
    xbutton.y = loc.y;
    xbutton.button = Button1;

    _check_grab(widget, &xbutton, widget->app);
    _has_pointer(widget, &xbutton);
    if (widget->flags & HAS_POINTER) widget->state = 1;
    else widget->state = 0;
    _check_enum(widget, &xbutton);

    if (widget->func.button_release_callback)
        widget->func.button_release_callback(widget, &xbutton, NULL);
    [self setNeedsDisplay:YES];
    
}

- (void)mouseDragged:(NSEvent *)event {
   if (widget->state == 4) return;
   if (!widget) return;
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];

    XMotionEvent xmotion = {0};
    xmotion.x = loc.x;
    xmotion.y = loc.y;

    // change value only while dragging
    adj_set_motion_state(widget, xmotion.x, xmotion.y);
    
    if (widget->func.motion_callback)
        widget->func.motion_callback(widget, &xmotion, NULL);
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event {
    if (widget->state == 4) return;
     
}


- (void)mouseEntered:(NSEvent *)event {
    if (widget->state == 4) return;
   
}

- (void)mouseExited:(NSEvent *)event {
    if (widget->state == 4) return;
  
}

- (void)scrollWheel:(NSEvent *)event {
    if (widget->state == 4) return;
   
}

@end

Display* os_open_display(char* display_name) { 
    return nullptr; 
}
void os_close_display(Display* dpy) {

}

Window os_get_root_window(Widget_t* w) { 
    return nil; 
}

void os_destroy_window(Widget_t* w) {
    if (!w || !w->widget) return;

    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow*)obj;

        // Push window to the back to avoid focus going to Finder
        [win orderBack:nil];
        [win close];
    } else if ([obj isKindOfClass:[NSView class]]) {
        [(NSView*)obj removeFromSuperview];
    }

    // Notify host that GUI is closed
    if (w->func.mem_free_callback) {
        w->func.mem_free_callback(w, NULL);
    }

    // Mark as destroyed
    w->state = 4;
}


void os_translate_coords(Widget_t *w, Window widget, Window root, int x, int y, int *rx, int *ry) {
    if (!widget) return;

    id obj = (__bridge id)widget;

    if ([obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;
        NSWindow *window = [view window];
        if (!window) return;

        NSPoint localPoint = NSMakePoint(x, y);
        NSPoint screenPoint = [view convertPoint:localPoint toView:nil];
        NSPoint windowPoint = [window convertRectToScreen:NSMakeRect(screenPoint.x, screenPoint.y, 0, 0)].origin;

        *rx = (int)windowPoint.x;
        *ry = (int)([[NSScreen mainScreen] frame].size.height - windowPoint.y);
    } else if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow *)obj;
        NSPoint winOrigin = [win frame].origin;
        *rx = (int)winOrigin.x + x;
        *ry = (int)([[NSScreen mainScreen] frame].size.height - winOrigin.y) + y;
    }
}

void os_get_window_metrics(Widget_t *w, Metrics_t *metrics) {
    if (!w || !w->widget) return;

    NSView *view = (__bridge NSView *)w->widget;
    NSRect frame = [view frame];

    metrics->visible = YES;
    metrics->x = (int)frame.origin.x;
    metrics->y = (int)frame.origin.y;
    metrics->width = (int)frame.size.width;
    metrics->height = (int)frame.size.height;
}

void os_set_window_min_size(Widget_t* w, int min_width, int min_height,
                            int base_width, int base_height) {
    if (!w || !w->widget) return;
    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSWindow class]]) {
        // Set minimum content size for NSWindow
        [(NSWindow*)obj setContentMinSize:NSMakeSize(min_width, min_height)];
    }
}

void os_move_window(Display *dpy, Widget_t *w, int x, int y) {
    if (!w || !w->widget) return;

    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;
        NSWindow *window = [view window];
        if (!window) return;

        NSRect frame = [window frame];
        NSRect screenFrame = [[NSScreen mainScreen] frame];
        NSPoint newOrigin = NSMakePoint(x, screenFrame.size.height - frame.size.height - y);

        [window setFrameOrigin:newOrigin];
    } else if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow *)obj;
        NSRect frame = [win frame];
        NSRect screenFrame = [[NSScreen mainScreen] frame];
        NSPoint newOrigin = NSMakePoint(x, screenFrame.size.height - frame.size.height - y);
        [win setFrameOrigin:newOrigin];
    }
}

void os_resize_window(Display* dpy, Widget_t* w, int width, int height) {
    if (!w || !w->widget) return;
    id obj = (__bridge id)w->widget;

    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *window = (NSWindow *)obj;

        // Set content size so client area matches requested size, just like on Windows
        [window setContentSize:NSMakeSize(width, height)];
    } else if ([obj isKindOfClass:[NSView class]]) {
        [(NSView *)obj setFrameSize:NSMakeSize(width, height)];
    }
}

void os_get_surface_size(cairo_surface_t* surface, int* width, int* height) {
    if (!surface) return;
    *width = cairo_image_surface_get_width(surface);
    *height = cairo_image_surface_get_height(surface);
}

void os_set_widget_surface_size(Widget_t* w, int width, int height) {
    if (!w) return;
    if (w->cr) cairo_destroy(w->cr);
    if (w->surface) cairo_surface_destroy(w->surface);
    w->surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    w->cr = cairo_create(w->surface);
}

void os_create_main_window_and_surface(Widget_t* w, Xputty* app, Window win,
                                       int x, int y, int width, int height) {
  
    childlist_add_child(app->childlist, w);

    if (win == (Window)-1) {
        // Main application window
        NSRect rect = NSMakeRect(x, y, width, height);

        NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                       styleMask:(NSWindowStyleMaskTitled |
                                                                  NSWindowStyleMaskClosable |
                                                                  NSWindowStyleMaskResizable)
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];

        XWidgetView *view = [[XWidgetView alloc] initWithWidget:w frame:NSMakeRect(0, 0, width, height)];
        [window setContentView:view];
        [window setTitle:@"Xputty macOS Window"];
        [window makeKeyAndOrderFront:nil];
        if (x == 0 && y == 0) {
            [window center];
        }
        // Store view as widget, consistent with other platforms
        w->widget = (__bridge Window)view;
        // Store the actual NSWindow separately if needed later
        w->parent_struct = (__bridge void *)window;

    } else if (win == (Window)kCGNullWindowID) {
    
    // Use parent_struct as NSView* for popup positioning
    NSView *parentView = (__bridge NSView *)w->parent_struct;
    NSWindow *parentWindow = [parentView window];

    // Convert the bounds of the parent view (e.g. ComboBox) to screen coordinates
    NSRect widgetRect = [parentView convertRect:[parentView bounds] toView:nil];
    NSPoint screenPoint = [parentWindow convertRectToScreen:widgetRect].origin;
    NSRect popupRect = NSMakeRect(screenPoint.x, screenPoint.y - height, width, height);

    NSWindow *popup = [[NSWindow alloc] initWithContentRect:popupRect
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

    [popup setOpaque:NO];
    [popup setBackgroundColor:[NSColor clearColor]];
    [popup setLevel:NSFloatingWindowLevel];
    [popup setHasShadow:YES];
    [popup setIgnoresMouseEvents:NO];
    [popup setReleasedWhenClosed:NO];

    XWidgetView *view = [[XWidgetView alloc] initWithWidget:w frame:NSMakeRect(0, 0, width, height)];
    [popup setContentView:view];
    [popup makeFirstResponder:view];

    // Use NSWindow as widget, so it can be shown/hidden correctly
    w->widget = (__bridge Window)popup;

    // Use view for drawing (optional, only if needed elsewhere)
    w->parent_struct = (__bridge void *)view;
    [popup makeKeyAndOrderFront:nil];

    } else if (win) {
        // Embedded widget inside another parent view
        NSView *parentView = (__bridge NSView *)win;
        NSRect rect = NSMakeRect(x, y, width, height);
        XWidgetView *view = [[XWidgetView alloc] initWithWidget:w frame:rect];
        [parentView addSubview:view];
        w->widget = (__bridge Window)view;
        w->parent_struct = (__bridge void *)parentView;
    }
    w->surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    w->cr = cairo_create(w->surface);
    os_set_window_min_size(w, width / 2, height / 2, width, height);
    //os_move_window(NULL, w, 200, 100);
}


void os_create_widget_window_and_surface(Widget_t* w, Xputty* app, Widget_t* parent,
                                         int x, int y, int width, int height) {
    if (!w || !parent || !parent->widget || width <= 1 || height <= 1) return;

    childlist_add_child(app->childlist, w);

    NSView *parentView = nil;
    id pobj = (__bridge id)parent->widget;
    if ([pobj isKindOfClass:[NSWindow class]]) {
        parentView = [(NSWindow*)pobj contentView];
    } else if ([pobj isKindOfClass:[NSView class]]) {
        parentView = (NSView*)pobj;
    } else {
        return;
    }

    NSRect frame = NSMakeRect(x, y, width, height);
    if (NSIsEmptyRect(frame)) return;
     // Create Cairo surface and context for drawing
    w->surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    w->cr = cairo_create(w->surface);
    // Create a custom NSView for the widget
    XWidgetView *view = [[XWidgetView alloc] initWithWidget:w frame:frame];
    if (!view) return;

    // Add the new view to its parent
    [parentView addSubview:view];
    w->widget = (__bridge Window)view;

}    

void os_set_title(Widget_t* w, const char* title) {
    if (!w || !w->widget) return;
    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSWindow class]]) {
        [(NSWindow*)obj setTitle:[NSString stringWithUTF8String:title]];
    }
}

void os_widget_show(Widget_t* w) {
    if (!w || !w->widget) return;
    id obj = (__bridge id)w->widget;

    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow*)obj;

        if (win.frame.size.width > 1 && win.frame.size.height > 1) {
            // Show window *without* stealing focus
            [win orderFrontRegardless];
        }
    } else if ([obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView*)obj;

        if (view.frame.size.width > 1 && view.frame.size.height > 1) {
            [view setHidden:NO];
            [view setNeedsDisplay:YES];
        }
    }
}


void os_widget_hide(Widget_t* w) {
    if (!w || !w->widget) return;

    id obj = (__bridge id)w->widget;

    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow*)obj;

        // Move window to back before hiding — helps restore focus to host (e.g. Carla)
        [win orderBack:nil];
        [win orderOut:nil];
    } else if ([obj isKindOfClass:[NSView class]]) {
        [(NSView*)obj setHidden:YES];
    }

    // Mark the widget as hidden, as on Linux
    w->flags |= HIDE_ON_DELETE;
}

void os_expose_widget(Widget_t* w) {
    if (!w || !w->widget || !w->surface || !w->cr) return;
    if (w->state == 4) return; // WIDGET DESTROYED/DEACTIVATED

    transparent_draw(w, NULL);

    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSWindow class]]) {
        [[(NSWindow*)obj contentView] setNeedsDisplay:YES];
    } else if ([obj isKindOfClass:[NSView class]]) {
        [(NSView*)obj setNeedsDisplay:YES];
    }
}

void os_send_configure_event(Widget_t* w, int x, int y, int width, int height) {
   //NOTHING
}

void os_send_button_press_event(Widget_t* w) {
   //NOTHING
}

void os_send_button_release_event(Widget_t* w) {
   //NOTHING
}

void os_adjustment_callback(void* w_, void* user_data) {
    Widget_t *w = (Widget_t *)w_;
    transparent_draw(w, user_data);
}

bool os_get_keyboard_input(Widget_t* w, XKeyEvent* key, char* buf, size_t bufsize) {
    if (bufsize < 2) return false;
    buf[0] = (char)key->keycode;
    buf[1] = 0;
    return true;
}

void os_free_pixmap(Widget_t* w, Pixmap pixmap) {}

void os_quit(Widget_t* w) {
    if (!w) return;

    // Safely close only this widget
    os_destroy_window(w);
}

void os_quit_widget(Widget_t* w) { os_destroy_window(w); }

Atom os_register_widget_destroy(Widget_t* wid) { return 0; }
Atom os_register_wm_delete_window(Widget_t* wid) { return 0; }

void os_widget_event_loop(void* w_, void* event, Xputty* main, void* user_data) {
   //Nothing
}

void os_run_embedded(Xputty* main) {
    // LV2 plugin does not control the event loop.
    // All events are dispatched via host's NSApplication.
}

void os_send_systray_message(Widget_t* w) {
    //Nothing
}
void os_show_tooltip(Widget_t* wid, Widget_t* w) {
    //Nothing
}

void os_main_run(Xputty* main) {
    // No-op: LV2 plugin must not start its own runloop.
}

} // extern "C"

#endif // __APPLE__