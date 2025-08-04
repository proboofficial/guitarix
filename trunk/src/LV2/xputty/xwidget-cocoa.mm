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
       NSLog(@"[drawRect] Surface NULL for widget: %p", widget);
       return;
    }
    if (widget->flags & IS_POPUP) {
    // To jest główny widget (nie popup) – zawsze go rysuj ponownie
    [self setNeedsDisplay:YES];
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
    if (!widget) return;
    if (widget->state == 4) return;

    XButtonEvent xbutton;
    xbutton.window = (__bridge Window)(self.window);
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    xbutton.x = loc.x;
    xbutton.y = loc.y;
    xbutton.button = Button1;

    widget->pos_x = loc.x;
    widget->pos_y = loc.y;

    if (widget->flags & HAS_TOOLTIP) hide_tooltip(widget);
    if (widget->flags & IS_POPUP) [self setNeedsDisplay:YES];
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
    if (widget->flags) widget->state = 1;
    else widget->state = 0;
    _check_enum(widget, &xbutton);
    Widget_t* combo = (Widget_t*)widget->parent;
    if (combo->func.expose_callback) {
        combo->func.expose_callback(combo, NULL);
    }
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
    if (widget->flags & IS_WINDOW) return;
    widget->state=1;
    [self setNeedsDisplay:YES];
   
}

- (void)mouseExited:(NSEvent *)event {
    if (widget->state == 4) return;
    if (widget->flags & IS_WINDOW) return;
    widget->state=0;
    [self setNeedsDisplay:YES];
  
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

        NSLog(@"[os_translate_coords] NSView: localPoint=(%d,%d), screenPoint=(%.1f,%.1f), windowPoint=(%.1f,%.1f), translated=(%d,%d)",
              x, y, screenPoint.x, screenPoint.y, windowPoint.x, windowPoint.y, *rx, *ry);
    } else if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow *)obj;
        NSPoint winOrigin = [win frame].origin;
        *rx = (int)winOrigin.x + x;
        *ry = (int)([[NSScreen mainScreen] frame].size.height - winOrigin.y) + y;

        NSLog(@"[os_translate_coords] NSWindow: winOrigin=(%.1f,%.1f), input=(%d,%d), translated=(%d,%d)",
              winOrigin.x, winOrigin.y, x, y, *rx, *ry);
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
     if (w->cr) {
        cairo_destroy(w->cr);
        w->cr = NULL;
    }
    if (w->surface) {
        cairo_surface_destroy(w->surface);
        w->surface = NULL;
    }

    // Create new surface and cr with actual size
    w->surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    w->cr = cairo_create(w->surface);
    id obj = (__bridge id)w->widget;

    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *window = (NSWindow *)obj;

        [window setContentSize:NSMakeSize(width, height)];
        NSView *contentView = [window contentView];
        [contentView setNeedsLayout:YES];
        [contentView layoutSubtreeIfNeeded];
        [contentView setNeedsDisplay:YES];
        [contentView displayIfNeeded];

        NSSize contentSize = [contentView frame].size;
        NSRect windowFrame = [window frame];
        NSLog(@"[os_resize_window] Requested size: %dx%d", width, height);
        NSLog(@"[os_resize_window] ContentView size after resize: %.0fx%.0f", contentSize.width, contentSize.height);
        NSLog(@"[os_resize_window] Window frame size after resize: %.0fx%.0f", windowFrame.size.width, windowFrame.size.height);


    } else if ([obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;
        [view setFrameSize:NSMakeSize(width, height)];
        [view setNeedsLayout:YES];
        [view layoutSubtreeIfNeeded];
        [view setNeedsDisplay:YES];
        [view displayIfNeeded];

        NSSize newSize = [view frame].size;
        NSLog(@"[os_resize_window] NSView resized to: %.0fx%.0f", newSize.width, newSize.height);
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
    

    if (win == (Window)-1) {
        childlist_add_child(app->childlist, w);
        // Main application window
        NSRect rect = NSMakeRect(x, y, width, height);

        NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                       styleMask:(NSWindowStyleMaskTitled |
                                                                  NSWindowStyleMaskClosable |
                                                                  NSWindowStyleMaskResizable)
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];

        // Create View, set widget
        XWidgetView *view = [[XWidgetView alloc] initWithWidget:w frame:NSMakeRect(0, 0, width, height)];
        [window setContentView:view];
        [window setTitle:@"Xputty macOS Window"];
        [window makeKeyAndOrderFront:nil];

        // Remember View and Widget
        w->widget = (__bridge Window)view;
        w->parent_struct = (__bridge void *)window;

        // Create Cairo surface and context for drawing
        w->surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
        w->cr = cairo_create(w->surface);

    } else if (win) {
        childlist_add_child(app->childlist, w);
        // Embedded widget inside another parent view
        NSView *parentView = (__bridge NSView *)win;
        NSRect rect = NSMakeRect(x, y, width, height);

        XWidgetView *view = [[XWidgetView alloc] initWithWidget:w frame:rect];
        [parentView addSubview:view];
        w->widget = (__bridge Window)view;
        w->parent_struct = (__bridge void *)parentView;

        w->surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
        w->cr = cairo_create(w->surface);
    } else {
    childlist_add_child(app->childlist, w);
    NSRect popupRect = NSMakeRect(x, y, width, height);

    // Create NSPanel as popup window
    NSPanel *popup = [[NSPanel alloc] initWithContentRect:popupRect
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];

    // set types for popup
    [popup setLevel:NSPopUpMenuWindowLevel];
    [popup setHasShadow:YES];
    [popup setOpaque:NO];
    [popup setBackgroundColor:[NSColor clearColor]];
    [popup setHidesOnDeactivate:YES]; // opcjonal
    [popup setReleasedWhenClosed:NO];
    [popup setBecomesKeyOnlyIfNeeded:YES];
    [popup setIgnoresMouseEvents:NO];

   
    // Create View Popuop
    XWidgetView *popupView = [[XWidgetView alloc] initWithWidget:w frame:NSMakeRect(0, 0, width, height)];
    [popup setContentView:popupView];

    // Set NSPanel and NSView for Xputty
    w->widget = (__bridge Window)popup;
    w->parent_struct = (__bridge void *)popupView;

    // Create Cairo surface and context for drawing
    w->surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    w->cr = cairo_create(w->surface);

    NSLog(@"[debug] popup: %0.0fx%0.0f,  popupview: %0.0fx%0.0f",
          popupView.frame.size.width, popupView.frame.size.height,
          popup.frame.size.width, popup.frame.size.height);

    NSLog(@"view.frame = %@, window.contentView.frame = %@",
          NSStringFromRect(popupView.frame),
          NSStringFromRect(popup.contentView.frame));
    }



    os_set_window_min_size(w, width / 2, height / 2, width, height);
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
    
    [parentView setNeedsDisplay:YES];
    w->widget = (__bridge Window)view;
}    

void os_set_title(Widget_t* w, const char* title) {
    if (!w || !w->widget) return;
    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSWindow class]]) {
        [(NSWindow*)obj setTitle:[NSString stringWithUTF8String:title]];
    }
}

void os_widget_show(Widget_t *w) {
    if (!w || !w->widget) return;

    id obj = (__bridge id)w->widget;

    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow *)obj;

        [win orderFront:nil];
        NSView *contentView = [win contentView];
        [contentView setNeedsLayout:YES];
        [contentView layoutSubtreeIfNeeded];

    } else if ([obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;

        [view setHidden:NO];
        [view setNeedsDisplay:YES];

        NSView *superview = [view superview];
        if (superview) {
            [superview setNeedsLayout:YES];
            [superview layoutSubtreeIfNeeded];
        }
        [view displayIfNeeded];
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
    if (w->state == 4) return;

    transparent_draw(w, NULL);

    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSWindow class]]) {
        NSView *contentView = [(NSWindow*)obj contentView];
        [contentView setNeedsDisplay:YES];
        [contentView displayIfNeeded];
    } else if ([obj isKindOfClass:[NSView class]]) {
        [(NSView*)obj setNeedsDisplay:YES];
        [(NSView*)obj displayIfNeeded];
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

void os_adjustment_callback(void *w_, void *user_data) {
    Widget_t *w = (Widget_t *)w_;
    transparent_draw(w, user_data);

    id obj = (__bridge id)w->widget;
    if ([obj isKindOfClass:[NSWindow class]]) {
        NSView *contentView = [(NSWindow*)obj contentView];
        [contentView setNeedsDisplay:YES];
        [contentView displayIfNeeded];
    } else if ([obj isKindOfClass:[NSView class]]) {
        [(NSView*)obj setNeedsDisplay:YES];
        [(NSView*)obj displayIfNeeded];
    }
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