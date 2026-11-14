package com.vhaiup.filtervpn;

import android.os.Bundle;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.vhaiup.vpn.NativeBridge;

/**
 * Entry screen. In phase 1 this only proves that the Java and native (NDK)
 * parts are built, packaged and linked correctly.
 */
public class MainActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        TextView status = findViewById(R.id.native_status);
        String version;
        try {
            version = NativeBridge.version();
        } catch (UnsatisfiedLinkError e) {
            version = "not loaded (" + e.getMessage() + ")";
        }
        status.setText(getString(R.string.status_native, version));
    }
}
