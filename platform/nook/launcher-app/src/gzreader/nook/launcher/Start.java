package gzreader.nook.launcher;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;

/**
 * GZreader's icon: writes "start" into the pipe GZreader's helper
 * (/data/gzreader/launcher.sh, running as root) waits on. Starting GZreader
 * needs root, which an app can't have on the Nook (its su is for adb only).
 * Android 1.5's API only.
 */
public class Start extends Activity {
    static final String PIPE = "/data/gzreader/launch/start";
    static final String SET_UP = "GZreader's launcher helper isn't set up.\n\n"
        + "Connect the Nook to a computer and run:\n"
        + "adb shell sh /data/gzreader/launcher.sh install";

    private final Handler handler = new Handler();
    private volatile boolean sent;
    private TextView text;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        text = new TextView(this);
        text.setTextSize(18);
        text.setPadding(24, 24, 24, 24);
        setContentView(text);
        if (!new File(PIPE).exists()) {
            text.setText(SET_UP);
            return;
        }
        text.setText("Starting GZreader...");
        new Thread() {
            @Override
            public void run() {
                // (waits if the helper isn't reading: the message below says so)
                try {
                    FileOutputStream out = new FileOutputStream(PIPE);
                    out.write("start\n".getBytes());
                    out.close();
                    sent = true;
                    handler.post(new Runnable() {
                        public void run() { finish(); }
                    });
                } catch (final Exception e) {
                    handler.post(new Runnable() {
                        public void run() { text.setText("GZreader couldn't be started: " + e.getMessage() + "\n\n" + SET_UP); }
                    });
                }
            }
        }.start();
        handler.postDelayed(new Runnable() {
            public void run() {
                if (!sent) text.setText("GZreader's launcher helper isn't running.\n\n"
                    + "Restart the Nook, or connect it to a computer and run:\n"
                    + "adb shell sh /data/gzreader/launcher.sh install");
            }
        }, 3000);
    }
}
