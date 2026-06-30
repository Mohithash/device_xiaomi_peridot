#!/bin/bash

# Sakura Priv
if [ ! -d "vendor/sakura-priv" ]; then
    git clone https://github.com/Sakura-Devices/vendor_sakura-priv vendor/sakura-priv
else
    echo "vendor/sakura-priv already exists, skipping..."
fi

# Gamebar
if [ ! -d "packages/apps/GameBar" ]; then
    git clone https://github.com/kenway214/packages_apps_GameBar.git packages/apps/GameBar
else
    echo "packages/apps/GameBar already exists, skipping..."
fi

# Bcr
if [ ! -d "vendor/bcr" ]; then
    git clone https://github.com/kenway214/vendor_bcr.git vendor/bcr
else
    echo "vendor/bcr already exists, skipping..."
fi

# Viper4A
if [ ! -d "packages/apps/ViPER4AndroidFX" ]; then
    git clone https://github.com/TogoFire/packages_apps_ViPER4AndroidFX.git packages/apps/ViPER4AndroidFX
else
    echo "packages/apps/ViPER4Android already exists, skipping..."
fi

# Miui Camera
if [ ! -d "device/xiaomi/peridot-miuicamera" ]; then
    git clone https://github.com/peridot-dev/android_device_xiaomi_peridot-miuicamera.git device/xiaomi/peridot-miuicamera
else
    echo "device/xiaomi/peridot-miuicamera already exists, skipping..."
fi

# Vendor Mi Cam
if [ ! -f "vendor/xiaomi/peridot-miuicamera/proprietary/system/priv-app/MiuiCamera/MiuiCamera.apk" ]; then
    git clone https://gitlab.com/NoPrincessHere/proprietary_vendor_xiaomi_peridot-miuicamera.git vendor/xiaomi/peridot-miuicamera
else
    echo "vendor/xiaomi/peridot-miuicamera already exists, skipping..."
fi
