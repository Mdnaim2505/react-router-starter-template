package com.vhaiup.filtervpn;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** Placeholder so the unit-test task runs in phase 1; real rule-matcher tests come in phase 4. */
public class SanityTest {
    @Test
    public void appIdIsStable() {
        assertEquals("com.vhaiup.filtervpn", BuildConfig.APPLICATION_ID);
    }
}
