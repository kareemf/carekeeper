# How to Export Your Data

Export your CareKeeper data to JSON format for backup, analysis, or migration to other systems. This guide covers the export process and what you can do with your data.

## Quick Steps

1. Open CareKeeper on iPhone
2. Tap Settings (gear icon)
3. Scroll to "Data Management"
4. Tap **Export Data**
5. Choose a caree or export all
6. Save or share the JSON file

## Why Export Data?

### Backup
- Create a local backup of your tracking data
- Protect against data loss
- Archive old data before deleting

### Analysis
- Import into spreadsheets (Excel, Numbers, Google Sheets)
- Create custom charts and reports
- Analyze patterns over time

### Portability
- Move data to another tracking system
- Share with healthcare providers
- Keep permanent records

### Privacy
- Keep a copy of your data outside of iCloud
- Delete from CareKeeper while keeping records
- Control your own data

## Exporting Data

### Step 1: Open Export Settings

1. Open CareKeeper on your iPhone
2. Tap the Settings icon (gear) in the top-right
3. Scroll to the "Data Management" section
4. Tap **Export Data**

[SCREENSHOT: Settings screen with Export Data option]

### Step 2: Choose What to Export

You have two options:

#### Export All Data
- Includes all carees
- All activity types for each caree
- All activities across all carees
- Largest file size
- Most comprehensive backup

[SCREENSHOT: Export all data option]

#### Export Single Caree
- Select one caree from the list
- Includes only that caree's activity types and activities
- Smaller file size
- Useful for sharing with specific caregivers or providers

[SCREENSHOT: Select caree to export]

### Step 3: Export Process

1. Tap your choice (All Data or specific caree)
2. CareKeeper prepares the export (may take a few seconds for large datasets)
3. The iOS share sheet appears
4. Choose where to save or how to share

[SCREENSHOT: Export in progress indicator]

### Step 4: Save or Share

Choose from these options:

#### Save to Files
1. Tap **Save to Files**
2. Choose a location (iCloud Drive, On My iPhone, etc.)
3. Tap **Save**

[SCREENSHOT: Save to Files interface]

#### Share via Email
1. Tap **Mail**
2. Enter recipient email
3. Add subject/message if desired
4. Tap **Send**

[SCREENSHOT: Email with JSON attachment]

#### AirDrop
1. Tap **AirDrop**
2. Select the receiving device
3. File transfers instantly

[SCREENSHOT: AirDrop to Mac]

#### Other Options
- Save to cloud services (Dropbox, Google Drive, OneDrive)
- Share to messaging apps
- Copy to Notes app

## Understanding the Export Format

### JSON Structure

CareKeeper exports data as JSON (JavaScript Object Notation)—a standard, human-readable format:

```json
{
  "exportDate": "2024-10-27T12:00:00Z",
  "version": "1.0",
  "carees": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Emma",
      "dateCreated": "2024-01-15T08:00:00Z",
      "activityTypes": [
        {
          "id": "660e8400-e29b-41d4-a716-446655440001",
          "name": "Bottle",
          "icon": "🍼",
          "hasQuantity": true,
          "quantityUnit": "oz",
          "hasLocation": false
        }
      ],
      "activities": [
        {
          "id": "770e8400-e29b-41d4-a716-446655440002",
          "activityTypeId": "660e8400-e29b-41d4-a716-446655440001",
          "dateTime": "2024-10-27T14:30:00Z",
          "quantity": 3.5,
          "notes": "Took bottle eagerly"
        }
      ]
    }
  ]
}
```

[SCREENSHOT: JSON file opened in text editor]

### What's Included

**Caree Data:**
- ID (unique identifier)
- Name
- Date created
- Profile photo (base64 encoded if present)

**Activity Type Data:**
- ID (unique identifier)
- Name
- Icon (emoji or SF Symbol name)
- Quantity settings (hasQuantity, quantityUnit)
- Location settings (hasLocation)
- List order
- Date created

**Activity Data:**
- ID (unique identifier)
- Activity type reference
- Date and time
- Quantity (if applicable)
- Location coordinates (if applicable)
- Notes (if present)
- Date created

### What's NOT Included

The following are not included in exports:
- ❌ CloudKit sharing metadata (participant lists, share IDs)
- ❌ Sync status information
- ❌ User notification preferences
- ❌ Other users' carees (only your own)

## Using Exported Data

### Import into Spreadsheet

To analyze in Excel, Numbers, or Google Sheets:

1. Use a JSON-to-CSV converter tool:
   - Online: [ConvertCSV.com](https://www.convertcsv.com/json-to-csv.htm)
   - Desktop: jq command-line tool
   - Python: pandas library
2. Convert JSON to CSV format
3. Open CSV in your spreadsheet app

[SCREENSHOT: JSON data in Excel]

### Import into Another App

If migrating to another tracking app:

1. Check if the other app supports JSON imports
2. Map CareKeeper fields to their fields:
   - caree.name → their subject/person field
   - activityType.name → their category/type field
   - activity.dateTime → their timestamp field
3. Use their import tool or API

### Create Custom Reports

With programming knowledge, you can:

**Python Example:**
```python
import json
import pandas as pd

# Load export
with open('carekeeper_export.json') as f:
    data = json.load(f)

# Extract activities
activities = []
for caree in data['carees']:
    for activity in caree['activities']:
        activities.append({
            'caree': caree['name'],
            'type': next(at['name'] for at in caree['activityTypes']
                        if at['id'] == activity['activityTypeId']),
            'dateTime': activity['dateTime'],
            'quantity': activity.get('quantity'),
            'notes': activity.get('notes')
        })

# Create DataFrame
df = pd.DataFrame(activities)

# Analyze
print(df.groupby('type')['quantity'].mean())
```

[SCREENSHOT: Custom analysis output]

### Archive Old Data

For long-term archival:

1. Export all data
2. Save to multiple locations:
   - External hard drive
   - Cloud storage (Google Drive, iCloud)
   - USB drive
3. Include a README explaining the data structure
4. Store in a folder with date: `CareKeeper_Backup_2024-10-27`

!!! tip "Best Practice"
    Export and backup your data monthly, especially if you're tracking critical medical information.

## Importing Data (Re-Import)

### Import Backup into CareKeeper

To restore a previous export:

1. Open CareKeeper settings
2. Tap **Import Data**
3. Choose the JSON file
4. CareKeeper restores:
   - Carees (if not already present)
   - Activity types (if not already present)
   - Activities

[SCREENSHOT: Import data option in settings]

!!! warning "Duplicate Handling"
    CareKeeper uses UUIDs to detect duplicates. Importing the same file twice won't create duplicates—it will skip existing records.

### Merge vs Replace

When importing:

**Merge** (default):
- Keeps existing data
- Adds new data from import
- Skips duplicates based on ID

**Replace** (optional):
- Deletes existing data
- Replaces with import data
- Use carefully!

[SCREENSHOT: Import options with merge/replace]

## Troubleshooting

### Export Button Not Responding
- Wait a few seconds (app may be syncing)
- Force close and reopen CareKeeper
- Check available storage space
- Try exporting one caree at a time

### Export File Too Large
- Export carees individually instead of all at once
- Delete old activities you don't need before exporting
- Compress the JSON file (zip) before sharing

### Cannot Open JSON File
- JSON files are text files—open with any text editor
- Use TextEdit (Mac), Notepad (Windows), or VS Code
- Verify file wasn't corrupted during transfer

### Import Failed
- Check JSON file is valid (use [JSONLint](https://jsonlint.com))
- Make sure file is a CareKeeper export (not modified)
- Try importing smaller portions
- Check CareKeeper version compatibility

For more help, see the [Troubleshooting Guide](../reference/troubleshooting.md).

## Privacy & Security

### Data Privacy
- Exported files contain all your tracking data
- Share carefully—only with trusted parties
- Consider removing sensitive notes before sharing
- Delete exported files from shared locations when no longer needed

### Encryption
- JSON exports are **not encrypted** by default
- If sharing via email/cloud, consider encrypting the file
- iOS Files app supports encryption via zip with password

### GDPR & Data Rights
Under data protection laws, you have the right to:
- ✅ Export your data (this feature)
- ✅ Delete your data (delete carees in app)
- ✅ Control who accesses your data (sharing controls)

## Best Practices

### Regular Backups
- 📅 Export monthly for ongoing tracking
- 💾 Save to multiple locations
- 🏷️ Name files with dates: `CareKeeper_2024-10.json`

### Before Major Changes
Export before:
- Deleting a caree
- Uninstalling CareKeeper
- Sharing with new participants
- iOS device upgrades

### Data Retention
- Keep exports for as long as relevant (medical records: years, pet care: months)
- Delete sensitive data when no longer needed
- Follow your local data retention laws

## Related Guides

- [Understanding Security & Privacy](../explanation/security-privacy.md)
- [Troubleshooting](../reference/troubleshooting.md)
- [FAQ](../reference/faq.md)
