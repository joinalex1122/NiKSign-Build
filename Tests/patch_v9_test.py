"""Automated test suite for NiKPatchV9Engine rules (%3105_Overwrite%, %3105_MatchPrefix%, %3105_Remove%, and canRemove).
Verifies both the Swift implementation structure in Native/Dependencies/NiKPatchV9Engine.swift
and the exact reference merge semantics across XML/binary plists and JSON payloads.
"""
from pathlib import Path
import base64
import json
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENGINE_PATH = ROOT / "Native/Dependencies/NiKPatchV9Engine.swift"
SMOKE_PATH = ROOT / "Tests/PatchV9Smoke.swift"


class NiKPatchV9ReferenceMerger:
    """Reference verifier mirroring NiKDynamicPayloadMerger in Native/Dependencies/NiKPatchV9Engine.swift."""
    OVERWRITE = "%3105_Overwrite%"
    REMOVE = "%3105_Remove%"
    MATCH_PREFIX = "%3105_MatchPrefix%"

    @classmethod
    def strip_overwrite_prefix(cls, filename: str):
        if filename.startswith(cls.OVERWRITE):
            stripped = filename[len(cls.OVERWRITE):]
            return (stripped if stripped else filename), True
        return filename, False

    @classmethod
    def find_single_matching_key(cls, target: dict, prefix: str) -> str:
        if not prefix:
            raise ValueError("Empty %3105_MatchPrefix% selector")
        matches = []
        for k in target.keys():
            if k.startswith(prefix):
                suffix = k[len(prefix):]
                if suffix and "/" not in suffix:
                    matches.append(k)
        if len(matches) != 1:
            raise ValueError(f"%3105_MatchPrefix% '{prefix}' matched {len(matches)} keys (expected exactly 1)")
        return matches[0]

    @staticmethod
    def exact_placeholder_id(text: str):
        if text.startswith("{{") and text.endswith("}}") and len(text) > 4:
            inner = text[2:-2]
            if "{{" not in inner and "}}" not in inner:
                return inner.strip()
        return None

    @classmethod
    def coerce_typed_value(cls, raw: str, field: dict, is_plist: bool):
        ftype = field.get("type", "string").lower()
        if ftype == "string":
            return raw
        if ftype in ("boolean", "bool"):
            norm = raw.strip().lower()
            if norm in ("true", "1"):
                return True
            if norm in ("false", "0"):
                return False
            raise ValueError(f"Invalid boolean: {raw}")
        if ftype in ("integer", "int"):
            return int(raw.strip())
        if ftype in ("double", "float", "number"):
            return float(raw.strip())
        if ftype == "data":
            enc = (field.get("encoding") or "base64").lower()
            raw_bytes = raw.encode("utf-8") if enc == "utf8" else base64.b64decode(raw.strip())
            return raw_bytes if is_plist else base64.b64encode(raw_bytes).decode("ascii")
        return raw

    @classmethod
    def merge_dicts(cls, target: dict, payload: dict, fields_by_id: dict, user_values: dict, is_plist: bool) -> dict:
        if payload.get(cls.OVERWRITE) is True:
            result = {}
        else:
            result = dict(target)

        for raw_key, raw_val in payload.items():
            if raw_key == cls.OVERWRITE:
                continue
            if raw_key.startswith(cls.MATCH_PREFIX):
                prefix = raw_key[len(cls.MATCH_PREFIX):]
                resolved_key = cls.find_single_matching_key(result, prefix)
            else:
                resolved_key = raw_key

            if isinstance(raw_val, str):
                if raw_val == cls.REMOVE:
                    result.pop(resolved_key, None)
                    continue
                exact_id = cls.exact_placeholder_id(raw_val)
                if exact_id and exact_id in fields_by_id:
                    field = fields_by_id[exact_id]
                    uval = user_values.get(exact_id, {})
                    if field.get("canRemove") and uval.get("removeField"):
                        result.pop(resolved_key, None)
                        continue
                    raw_input = uval.get("stringValue", field.get("default", ""))
                    result[resolved_key] = cls.coerce_typed_value(raw_input, field, is_plist)
                    continue
                # Ensure no removable placeholder is embedded mid-string
                for fid, field in fields_by_id.items():
                    if field.get("canRemove") and user_values.get(fid, {}).get("removeField"):
                        if f"{{{{{fid}}}}}" in raw_val:
                            raise ValueError(f"Removable placeholder {{{{{fid}}}}} cannot be removed mid-string")
                out_str = raw_val
                for fid, field in fields_by_id.items():
                    val = user_values.get(fid, {}).get("stringValue", field.get("default", ""))
                    out_str = out_str.replace(f"{{{{{fid}}}}}", str(val))
                result[resolved_key] = out_str
            elif isinstance(raw_val, dict):
                nested_target = result.get(resolved_key) if isinstance(result.get(resolved_key), dict) else {}
                result[resolved_key] = cls.merge_dicts(nested_target, raw_val, fields_by_id, user_values, is_plist)
            elif isinstance(raw_val, list):
                new_list = []
                for item in raw_val:
                    if isinstance(item, str):
                        for fid, field in fields_by_id.items():
                            if field.get("canRemove") and user_values.get(fid, {}).get("removeField"):
                                if f"{{{{{fid}}}}}" in item:
                                    raise ValueError(f"Removable placeholder {{{{{fid}}}}} cannot be removed inside Array")
                        exact_id = cls.exact_placeholder_id(item)
                        if exact_id and exact_id in fields_by_id:
                            field = fields_by_id[exact_id]
                            raw_input = user_values.get(exact_id, {}).get("stringValue", field.get("default", ""))
                            new_list.append(cls.coerce_typed_value(raw_input, field, is_plist))
                        else:
                            new_list.append(item)
                    else:
                        new_list.append(item)
                result[resolved_key] = new_list
            else:
                result[resolved_key] = raw_val
        return result


class PatchV9EngineTests(unittest.TestCase):
    def setUp(self):
        self.fields = {
            "display_name": {"id": "display_name", "label": "Tên hiển thị", "type": "string", "default": "3105", "canRemove": True},
            "enabled": {"id": "enabled", "label": "Bật tính năng", "type": "boolean", "default": "true"},
            "subscriber_cache": {"id": "subscriber_cache", "label": "Subscriber cache", "type": "data", "encoding": "utf8", "default": "{}"},
        }

    def test_swift_engine_and_smoke_files_present_and_complete(self):
        self.assertTrue(ENGINE_PATH.is_file(), "Missing NiKPatchV9Engine.swift")
        self.assertTrue(SMOKE_PATH.is_file(), "Missing PatchV9Smoke.swift")
        source = ENGINE_PATH.read_text()
        for token in [
            'static let overwriteMarker = "%3105_Overwrite%"',
            'static let removeMarker = "%3105_Remove%"',
            'static let matchPrefixMarker = "%3105_MatchPrefix%"',
            'func stripOverwritePrefix(fromFilename filename: String)',
            'func readMatchedPrefixValues(',
            'func findSingleMatchingKey(in dict: [String: Any], prefix: String)',
            'ensureNoEmbeddedRemovablePlaceholder',
            'ensureNoRemovablePlaceholderInArrayElement',
            'field.canRemove == true && userEntry?.removeField == true',
        ]:
            self.assertIn(token, source)

    def test_overwrite_filename_prefix_and_nested_dictionary_overwrite(self):
        clean, has_prefix = NiKPatchV9ReferenceMerger.strip_overwrite_prefix("%3105_Overwrite%com.locket.Locket.plist")
        self.assertEqual(clean, "com.locket.Locket.plist")
        self.assertTrue(has_prefix)

        target = {
            "PreserveTop": 42,
            "Appearance": {"LegacyKey": "old", "Theme": "light"},
        }
        payload = {
            "Appearance": {
                "%3105_Overwrite%": True,
                "Mode": "compact",
            }
        }
        merged = NiKPatchV9ReferenceMerger.merge_dicts(target, payload, self.fields, {}, is_plist=True)
        self.assertEqual(merged["PreserveTop"], 42)
        self.assertEqual(merged["Appearance"], {"Mode": "compact"})

    def test_match_prefix_single_segment_matching_and_subpath_exclusion(self):
        target = {
            "https://api.revenuecat.com/v1/subscribers/RC_Device_12345": b'{"old":1}',
            "https://api.revenuecat.com/v1/subscribers/RC_Device_12345/offerings": b'{"offerings":[]}',
            "https://api.revenuecat.com/v1/subscribers/RC_Device_12345/attributes": b'{"attr":1}',
        }
        payload = {
            "%3105_MatchPrefix%https://api.revenuecat.com/v1/subscribers/": "{{subscriber_cache}}"
        }
        user_values = {
            "subscriber_cache": {"stringValue": '{"entitlements":{"gold":true}}', "removeField": False}
        }
        merged = NiKPatchV9ReferenceMerger.merge_dicts(target, payload, self.fields, user_values, is_plist=True)
        self.assertEqual(
            merged["https://api.revenuecat.com/v1/subscribers/RC_Device_12345"],
            b'{"entitlements":{"gold":true}}',
        )
        # Sub-paths containing '/' must not be matched or overwritten
        self.assertEqual(
            merged["https://api.revenuecat.com/v1/subscribers/RC_Device_12345/offerings"],
            b'{"offerings":[]}',
        )

    def test_match_prefix_rejects_zero_or_multiple_candidates(self):
        ambiguous_target = {
            "https://api.revenuecat.com/v1/subscribers/UserA": b"1",
            "https://api.revenuecat.com/v1/subscribers/UserB": b"2",
        }
        payload = {
            "%3105_MatchPrefix%https://api.revenuecat.com/v1/subscribers/": "{{subscriber_cache}}"
        }
        with self.assertRaises(ValueError):
            NiKPatchV9ReferenceMerger.merge_dicts(ambiguous_target, payload, self.fields, {}, is_plist=True)
        with self.assertRaises(ValueError):
            NiKPatchV9ReferenceMerger.merge_dicts({}, payload, self.fields, {}, is_plist=True)

    def test_remove_marker_and_can_remove_toggle(self):
        target = {
            "DisplayName": "OldName",
            "ObsoleteKey": "Legacy",
            "Enabled": False,
        }
        payload = {
            "DisplayName": "{{display_name}}",
            "ObsoleteKey": "%3105_Remove%",
            "Enabled": "{{enabled}}",
        }
        # Case A: removeField = False -> updates DisplayName and deletes ObsoleteKey
        merged_keep = NiKPatchV9ReferenceMerger.merge_dicts(
            target,
            payload,
            self.fields,
            {"display_name": {"stringValue": "Custom 3105", "removeField": False}, "enabled": {"stringValue": "true", "removeField": False}},
            is_plist=True,
        )
        self.assertEqual(merged_keep["DisplayName"], "Custom 3105")
        self.assertNotIn("ObsoleteKey", merged_keep)
        self.assertIs(merged_keep["Enabled"], True)

        # Case B: removeField = True on canRemove field -> deletes DisplayName key from target
        merged_removed = NiKPatchV9ReferenceMerger.merge_dicts(
            target,
            payload,
            self.fields,
            {"display_name": {"stringValue": "Custom 3105", "removeField": True}},
            is_plist=True,
        )
        self.assertNotIn("DisplayName", merged_removed)
        self.assertNotIn("ObsoleteKey", merged_removed)

    def test_can_remove_rejects_mid_string_or_array_elements(self):
        removal_values = {"display_name": {"stringValue": "X", "removeField": True}}
        with self.assertRaises(ValueError):
            NiKPatchV9ReferenceMerger.merge_dicts(
                {},
                {"Welcome": "Xin chào {{display_name}}"},
                self.fields,
                removal_values,
                is_plist=False,
            )
        with self.assertRaises(ValueError):
            NiKPatchV9ReferenceMerger.merge_dicts(
                {},
                {"Items": ["{{display_name}}"]},
                self.fields,
                removal_values,
                is_plist=False,
            )


if __name__ == "__main__":
    unittest.main()
