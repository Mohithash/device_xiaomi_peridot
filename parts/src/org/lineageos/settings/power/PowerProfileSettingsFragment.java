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

package org.lineageos.settings.power;

import android.content.ComponentName;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.service.quicksettings.TileService;

import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragment;
import androidx.preference.PreferenceManager;

import org.lineageos.settings.R;

/**
 * Lets the user pick a power profile directly, instead of only being able to
 * cycle through it via the QS tile. Deliberately does NOT duplicate
 * PowerProfileTileService's sysfs/notification/battery-saver logic here —
 * it only saves the desired profile and asks the tile to reconcile itself
 * via requestListeningState(), which re-runs its existing onStartListening()
 * comparison of saved vs. current profile. This keeps the "apply a profile"
 * logic in exactly one place.
 */
public class PowerProfileSettingsFragment extends PreferenceFragment
        implements Preference.OnPreferenceChangeListener {

    // Must match PowerProfileTileService.POWER_PROFILE_PREF_KEY
    private static final String POWER_PROFILE_PREF_KEY = "saved_power_profile";
    private static final String POWER_PROFILE_PREF = "power_profile_pref";

    private ListPreference mProfilePref;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        addPreferencesFromResource(R.xml.power_profile_settings);

        mProfilePref = (ListPreference) findPreference(POWER_PROFILE_PREF);
        int savedValue = getPrefs().getInt(POWER_PROFILE_PREF_KEY, 0);
        mProfilePref.setValue(String.valueOf(savedValue));
        updateSummary(mProfilePref.getValue());
        mProfilePref.setOnPreferenceChangeListener(this);
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        if (!POWER_PROFILE_PREF.equals(preference.getKey())) {
            return false;
        }

        String value = (String) newValue;
        getPrefs().edit().putInt(POWER_PROFILE_PREF_KEY, Integer.parseInt(value)).apply();
        updateSummary(value);

        TileService.requestListeningState(getActivity(),
                new ComponentName(getActivity(), PowerProfileTileService.class));
        return true;
    }

    private void updateSummary(String value) {
        int index = mProfilePref.findIndexOfValue(value);
        if (index >= 0) {
            mProfilePref.setSummary(mProfilePref.getEntries()[index]);
        }
    }

    private SharedPreferences getPrefs() {
        return PreferenceManager.getDefaultSharedPreferences(getActivity());
    }
}
