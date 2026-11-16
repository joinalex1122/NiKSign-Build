import Foundation

@main
struct PatchV9Smoke {
    static func main() throws {
        // 1. Test %3105_Overwrite% filename prefix stripping
        let (cleanName, hasOverwrite) = NiKDynamicPayloadMerger.stripOverwritePrefix(
            fromFilename: "%3105_Overwrite%com.locket.Locket.plist"
        )
        assert(cleanName == "com.locket.Locket.plist" && hasOverwrite)

        // 2. Build schema with string (canRemove: true), boolean, integer, and UTF-8 data fields
        let schema = NiKPatchSettingsSchema(
            schemaVersion: 1,
            fields: [
                NiKPatchSettingField(
                    id: "display_name",
                    label: "Tên hiển thị",
                    type: "string",
                    defaultValue: "3105",
                    canRemove: true
                ),
                NiKPatchSettingField(
                    id: "enabled",
                    label: "Bật tính năng",
                    type: "boolean",
                    defaultValue: "true"
                ),
                NiKPatchSettingField(
                    id: "subscriber_cache",
                    label: "Subscriber cache",
                    type: "data",
                    encoding: "utf8",
                    defaultValue: "{}"
                )
            ]
        )

        // 3. Prepare target plist with existing keys, nested dict, and a single device-specific RevenueCat subscriber key
        let initialTargetDict: [String: Any] = [
            "KeepMe": "Untouched",
            "ObsoleteKey": "ShouldBeRemoved",
            "Appearance": [
                "OldTheme": "Legacy",
                "OldFont": "System"
            ],
            "https://api.revenuecat.com/v1/subscribers/RCAnonymousID_998877": Data("{\"old\":true}".utf8),
            "https://api.revenuecat.com/v1/subscribers/RCAnonymousID_998877/offerings": Data("{\"offerings\":[]}".utf8)
        ]
        let targetData = try PropertyListSerialization.data(fromPropertyList: initialTargetDict, format: .binary, options: 0)

        let payloadDict: [String: Any] = [
            "DisplayName": "{{display_name}}",
            "Enabled": "{{enabled}}",
            "ObsoleteKey": "%3105_Remove%",
            "Appearance": [
                "%3105_Overwrite%": true,
                "Mode": "compact"
            ],
            "%3105_MatchPrefix%https://api.revenuecat.com/v1/subscribers/": "{{subscriber_cache}}"
        ]
        let payloadData = try PropertyListSerialization.data(fromPropertyList: payloadDict, format: .xml, options: 0)

        // 4. Test reading %3105_MatchPrefix% live value from target plist
        let prefill = try NiKDynamicPayloadMerger.readMatchedPrefixValues(
            fromTargetData: targetData,
            payloadData: payloadData,
            isPlist: true,
            schema: schema
        )
        assert(prefill["subscriber_cache"] == "{\"old\":true}")

        // 5. Test merging with typed values, %3105_Remove%, nested %3105_Overwrite%, and %3105_MatchPrefix%
        let userValues: [String: NiKPatchFieldUserValue] = [
            "display_name": NiKPatchFieldUserValue(stringValue: "NiKSign Pro", removeField: false),
            "enabled": NiKPatchFieldUserValue(stringValue: "true", removeField: false),
            "subscriber_cache": NiKPatchFieldUserValue(stringValue: "{\"pro\":true}", removeField: false)
        ]
        let mergedData = try NiKDynamicPayloadMerger.merge(
            targetData: targetData,
            payloadData: payloadData,
            isPlist: true,
            schema: schema,
            userValues: userValues
        )
        let mergedDict = try PropertyListSerialization.propertyList(from: mergedData, options: [], format: nil) as! [String: Any]
        assert(mergedDict["KeepMe"] as? String == "Untouched")
        assert(mergedDict["DisplayName"] as? String == "NiKSign Pro")
        assert(mergedDict["Enabled"] as? Bool == true)
        assert(mergedDict["ObsoleteKey"] == nil, "%3105_Remove% must delete ObsoleteKey")
        let appearance = mergedDict["Appearance"] as? [String: Any]
        assert(appearance?["OldTheme"] == nil && appearance?["Mode"] as? String == "compact", "%3105_Overwrite% must clear old nested keys")
        let updatedCache = mergedDict["https://api.revenuecat.com/v1/subscribers/RCAnonymousID_998877"] as? Data
        assert(String(decoding: updatedCache ?? Data(), as: UTF8.self) == "{\"pro\":true}")
        // Sub-path with '/' must remain untouched
        assert(mergedDict["https://api.revenuecat.com/v1/subscribers/RCAnonymousID_998877/offerings"] != nil)

        // 6. Test canRemove = true when removeField = true deletes the key cleanly
        var removalValues = userValues
        removalValues["display_name"] = NiKPatchFieldUserValue(stringValue: "Ignored", removeField: true)
        let removedFieldData = try NiKDynamicPayloadMerger.merge(
            targetData: targetData,
            payloadData: payloadData,
            isPlist: true,
            schema: schema,
            userValues: removalValues
        )
        let removedFieldDict = try PropertyListSerialization.propertyList(from: removedFieldData, options: [], format: nil) as! [String: Any]
        assert(removedFieldDict["DisplayName"] == nil, "canRemove with removeField=true must remove DisplayName key")

        // 7. Test safety guard: removable placeholder embedded mid-string or inside Array must abort safely
        let midStringPayload = try JSONSerialization.data(withJSONObject: ["Greeting": "Hello {{display_name}}!"])
        expectFailure {
            _ = try NiKDynamicPayloadMerger.merge(
                targetData: Data("{}".utf8),
                payloadData: midStringPayload,
                isPlist: false,
                schema: schema,
                userValues: removalValues
            )
        }
        let arrayPayload = try JSONSerialization.data(withJSONObject: ["Items": ["{{display_name}}"]])
        expectFailure {
            _ = try NiKDynamicPayloadMerger.merge(
                targetData: Data("{}".utf8),
                payloadData: arrayPayload,
                isPlist: false,
                schema: schema,
                userValues: removalValues
            )
        }

        // 8. Test safety guard: %3105_MatchPrefix% with 0 or 2 matches must abort safely
        let ambiguousTarget = try JSONSerialization.data(withJSONObject: [
            "prefix_deviceA": "1",
            "prefix_deviceB": "2"
        ])
        let prefixPayload = try JSONSerialization.data(withJSONObject: [
            "%3105_MatchPrefix%prefix_": "{{display_name}}"
        ])
        expectFailure {
            _ = try NiKDynamicPayloadMerger.merge(
                targetData: ambiguousTarget,
                payloadData: prefixPayload,
                isPlist: false,
                schema: schema,
                userValues: userValues
            )
        }

        print("PASS: PatchV9Smoke verified %3105_Overwrite%, %3105_MatchPrefix%, %3105_Remove%, and canRemove rules.")
    }

    static func expectFailure(_ body: () throws -> Void) {
        do {
            try body()
            fatalError("Expected failure for unsafe or ambiguous Patch v9 operation")
        } catch {}
    }
}
