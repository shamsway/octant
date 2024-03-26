# Set variables
$APPLIANCE_NAME="octantnode"
$OUTPUT_PATH = "../output-${APPLIANCE_NAME}"
$APPLIANCE_VERSION = "1"

# Create a backup of the OVF file
$ovfBackupPath = "${OUTPUT_PATH}/${APPLIANCE_NAME}_backup.ovf"
Copy-Item -Path "${OUTPUT_PATH}/${APPLIANCE_NAME}.ovf" -Destination $ovfBackupPath

# Copy cloud-init.xml to appliance.xml
Copy-Item -Path "cloud-init.xml" -Destination "appliance.xml"

# Remove manifest file
$manifest = @("${OUTPUT_PATH}/${APPLIANCE_NAME}.mf")
if (Test-Path $manifest) {
    Remove-Item $manifest -Force
}

# Read the OVF file content
$ovfContent = Get-Content "${OUTPUT_PATH}/${APPLIANCE_NAME}.ovf" -Raw

# Read the appliance.xml content
$applianceXmlContent = Get-Content "appliance.xml" -Raw

# Modify the VirtualHardwareSection tag
$ovfContent = $ovfContent -replace '<VirtualHardwareSection>', '<VirtualHardwareSection ovf:transport="com.vmware.guestInfo">'

# Insert the appliance.xml content before the closing </VirtualSystem> tag
$ovfContent = $ovfContent -replace "(</VirtualHardwareSection>\s*)(</VirtualSystem>)", "`$1`n$applianceXmlContent`$2"

# Remove the vmw:ExtraConfig lines
$ovfContent = $ovfContent -replace '<vmw:ExtraConfig ovf:required="false" vmw:key="nvram".*\n', ''
$ovfContent = $ovfContent -replace '<File ovf:href="${APPLIANCE_NAME}-file1.nvram".*\n', ''
$ovfContent = $ovfContent -replace '<vmw:ExtraConfig ovf:required="false" vmw:key="virtualhw.productcompatibility".*\n', ''
$ovfContent = $ovfContent -replace ' ovf:required="true"', ''

# Save the modified OVF content
Set-Content -Path "${OUTPUT_PATH}/${APPLIANCE_NAME}.ovf" -Value $ovfContent

# Run ovftool
ovftool --skipManifestCheck "${OUTPUT_PATH}/${APPLIANCE_NAME}.ovf" "${OUTPUT_PATH}/${APPLIANCE_NAME}.ova"

# Remove files if they exist
$files = @(
    "${OUTPUT_PATH}/${APPLIANCE_NAME}.mf",
    "${OUTPUT_PATH}/${APPLIANCE_NAME}.ovf",
    "${OUTPUT_PATH}/${APPLIANCE_NAME}-file1.nvram",
    "${OUTPUT_PATH}/${APPLIANCE_NAME}-disk1.vmdk"
)

foreach ($file in $files) {
    if (Test-Path $file) {
        Remove-Item $file -Force
    }
}