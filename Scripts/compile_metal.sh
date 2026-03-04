#!/bin/bash

# Script to manually compile MLX Metal kernels into a metallib
# This is needed because 'swift build' doesn't do it automatically.

BUILD_DIR=".build/arm64-apple-macosx/debug"
MLX_DIR=".build/checkouts/mlx-swift"
TEMP_DIR=".build/metal_tmp"

mkdir -p "$TEMP_DIR"
mkdir -p "$BUILD_DIR"

echo "--------------------------------------------------"
echo "Friday: Compiling Metal Kernels..."
echo "--------------------------------------------------"

# Define include paths
INC_GENERATED="$MLX_DIR/Source/Cmlx/mlx-generated/metal"

# Collect ONLY generated .metal files to avoid duplicate symbols
METAL_FILES=$(find "$INC_GENERATED" -maxdepth 1 -name "*.metal")

AIR_FILES=""
for f in $METAL_FILES; do
    name=$(basename "$f" .metal)
    echo "Compiling $name..."
    
    xcrun -sdk macosx metal -c \
        -I "$INC_GENERATED" \
        -I "$MLX_DIR/Source/Cmlx/mlx" \
        "$f" -o "$TEMP_DIR/$name.air"
    
    if [ $? -eq 0 ]; then
        AIR_FILES="$AIR_FILES $TEMP_DIR/$name.air"
    else
        echo "Failed to compile $f"
    fi
done

if [ -n "$AIR_FILES" ]; then
    echo "Linking AIR files into mlx.metallib..."
    xcrun -sdk macosx metallib $AIR_FILES -o "$BUILD_DIR/mlx.metallib"
    
    # Also copy as default.metallib
    cp "$BUILD_DIR/mlx.metallib" "$BUILD_DIR/default.metallib"
    
    echo "✅ Success! metallib created in $BUILD_DIR"
else
    echo "❌ Error: No AIR files created."
    exit 1
fi

rm -rf "$TEMP_DIR"
echo "--------------------------------------------------"
