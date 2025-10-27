# How to Create an Activity Type

Activity types are the building blocks of tracking in CareKeeper. This guide covers all options for creating and customizing activity types.

## Quick Steps

1. Open your caree's detail view
2. Tap **+ Add Activity Type**
3. Configure name, icon, and tracking options
4. Tap **Save**

## Detailed Instructions

### Open Activity Type Creation

1. Open CareKeeper and tap on a caree
2. In the "Activity Types" section, tap **+ Add Activity Type**
3. You'll see the activity type form

[SCREENSHOT: New activity type form]

### Choose a Name

1. Tap the **Name** field
2. Enter a clear, descriptive name (e.g., "Medication", "Walk", "Playtime")
3. Keep it short for better display on watch

!!! tip "Naming Best Practices"
    - Use clear, specific names ("Amoxicillin" vs "Medicine")
    - Keep under 20 characters for watch compatibility
    - Use consistent naming patterns ("Bottle", "Nursing", not "Fed bottle")

### Select an Icon

Icons help you quickly identify activity types. You can use:

#### Emojis
1. Tap the **Icon** field
2. Your emoji keyboard appears
3. Select any emoji (🍼, 💊, 🚶, etc.)

[SCREENSHOT: Emoji picker]

#### SF Symbols
1. Tap the **Icon** field
2. Type an SF Symbol name (e.g., "pill.fill", "figure.walk")
3. The symbol appears in the preview

[SCREENSHOT: SF Symbol selection]

!!! note "SF Symbols"
    SF Symbols are Apple's icon library. Search for symbols at [sf-symbols.com](https://developer.apple.com/sf-symbols/) or use common names like:
    - Medical: `pill.fill`, `cross.fill`, `heart.fill`
    - Activity: `figure.walk`, `figure.run`, `sportscourt.fill`
    - Food: `fork.knife`, `cup.and.saucer.fill`
    - General: `checkmark.circle.fill`, `star.fill`

### Configure Quantity Tracking

Enable this if you want to record amounts (e.g., ounces, doses, minutes):

1. Toggle **Has Quantity** to **ON**
2. Enter a **Unit** (e.g., "oz", "ml", "min", "tablets", "mg")
3. This unit will appear when tracking activities

[SCREENSHOT: Quantity configuration]

#### Examples of Quantity Use

| Activity Type | Quantity | Unit |
|--------------|----------|------|
| Bottle feeding | 3.5 | oz |
| Medication | 5 | mg |
| Nursing | 15 | min |
| Walk | 30 | min |
| Water | 8 | oz |

!!! tip "Decimal Values"
    Quantities support decimals, so you can track "3.5 oz" or "2.5 tablets" precisely.

### Configure Location Tracking

Enable this to record where activities occurred:

1. Toggle **Has Location** to **ON**
2. CareKeeper will request location permission if not granted
3. When tracking, your current location is automatically captured

[SCREENSHOT: Location toggle and permission request]

#### When to Use Location Tracking

**Useful for:**
- Walks (track your walking route)
- Outdoor activities (playground visits, park time)
- Travel (medical appointments, day trips)
- Multi-location care (daycare drop-off/pickup)

**Not useful for:**
- Home activities (feeding, diaper changes, naps)
- Medication at fixed locations
- Routine daily tasks

!!! warning "Privacy Note"
    Locations are synced via iCloud and visible to anyone you share the caree with. Only enable for activity types where location adds value.

### Save Your Activity Type

1. Review your configuration
2. Tap **Save** in the top-right corner
3. The activity type appears in your list

[SCREENSHOT: Saved activity type in list]

## Advanced Options

### Editing Activity Types

To modify an existing activity type:

1. Open the caree detail view
2. Find the activity type in the list
3. Swipe left and tap **Edit**
4. Make your changes
5. Tap **Save**

[SCREENSHOT: Swipe to edit activity type]

!!! note "Editing Limitations"
    Changing an activity type affects how new activities are tracked, but doesn't modify existing activities.

### Deleting Activity Types

!!! danger "Permanent Deletion"
    Deleting an activity type also deletes all activities of that type. This cannot be undone.

1. Swipe left on the activity type
2. Tap **Delete**
3. Confirm the deletion

[SCREENSHOT: Delete confirmation]

### Reordering Activity Types

Set the order for easier access:

1. Tap **Edit** in the Activity Types section
2. Drag the ☰ handle to reorder
3. Tap **Done**

!!! tip "Optimize for Watch"
    Put frequently-used types at the top. The watch app shows them in the same order.

[SCREENSHOT: Reordering with drag handles]

## Examples

### Example 1: Medication Tracking

**Scenario**: Track daily medication with dosage

- **Name**: "Amoxicillin"
- **Icon**: 💊 or "pill.fill"
- **Has Quantity**: ON
- **Unit**: "mg"
- **Has Location**: OFF

[SCREENSHOT: Medication activity type configuration]

### Example 2: Dog Walking

**Scenario**: Track walks with duration and location

- **Name**: "Walk"
- **Icon**: 🚶 or "figure.walk"
- **Has Quantity**: ON
- **Unit**: "min"
- **Has Location**: ON

[SCREENSHOT: Walk activity type configuration]

### Example 3: Simple Diaper Change

**Scenario**: Quick tracking without extra data

- **Name**: "Diaper Change"
- **Icon**: 🚼 or "figure.and.child.holdinghands"
- **Has Quantity**: OFF
- **Has Location**: OFF

[SCREENSHOT: Simple activity type configuration]

## Troubleshooting

### Icon Not Showing
- If using SF Symbol, verify the name is correct
- Try using an emoji instead for simplicity
- Leave blank to use default icon

### Cannot Enable Quantity
- Make sure you're editing (not viewing)
- Save and try again if toggle is unresponsive

### Activity Type Not Syncing
- Check internet connection
- Pull down to refresh on other devices
- Check sync status in settings

For more help, see the [Troubleshooting Guide](../reference/troubleshooting.md).

## Related Guides

- [How to Track an Activity](track-activity.md)
- [How to Use the Watch App](use-watch-app.md)
- [Understanding the Features](../reference/features.md)
