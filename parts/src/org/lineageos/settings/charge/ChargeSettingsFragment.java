/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.lineageos.settings.charge;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;

import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragment;
import androidx.preference.PreferenceManager;

import org.lineageos.settings.R;

/**
 * Lets the user pick a charge mode directly, instead of only being able to
 * cycle through OK -> COOL -> NUKE via the QS tile. Reads/writes the same
 * SharedPreferences key the tile uses, and drives the same enforcement
 * service, so both stay in sync no matter which one was used last.
 */
public class ChargeSettingsFragment extends PreferenceFragment
        implements Preference.OnPreferenceChangeListener {

    // Must match ChargeTileService.PREF_KEY
    private static final String PREF_KEY = "saved_charge_mode";
    private static final String CHARGE_MODE_PREF = "charge_mode_pref";

    private ListPreference mChargeModePref;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        addPreferencesFromResource(R.xml.charge_settings);

        mChargeModePref = (ListPreference) findPreference(CHARGE_MODE_PREF);
        int savedIndex = getPrefs().getInt(PREF_KEY, 0);
        mChargeModePref.setValue(String.valueOf(savedIndex));
        updateSummary(savedIndex);
        mChargeModePref.setOnPreferenceChangeListener(this);
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        if (!CHARGE_MODE_PREF.equals(preference.getKey())) {
            return false;
        }

        int index = Integer.parseInt((String) newValue);
        getPrefs().edit().putInt(PREF_KEY, index).apply();
        updateSummary(index);

        // Mirror ChargeTileService.onClick(): start/stop the enforcement
        // service based on the newly selected mode.
        Intent intent = new Intent(getActivity(), ChargeEnforcementService.class);
        if (index > 0) {
            getActivity().startService(intent);
        } else {
            getActivity().stopService(intent);
        }
        return true;
    }

    private void updateSummary(int index) {
        CharSequence[] entries = mChargeModePref.getEntries();
        if (index >= 0 && index < entries.length) {
            mChargeModePref.setSummary(entries[index]);
        }
    }

    private SharedPreferences getPrefs() {
        return PreferenceManager.getDefaultSharedPreferences(getActivity());
    }
}
