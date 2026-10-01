package main

import (
	"bytes"
	"encoding/base64"
	"encoding/xml"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// readPlist decodes the property list at path into maps, slices, strings,
// int64s, float64s, bools, time.Times and []bytes. macOS writes most of the
// system's plists in binary; those go through `plutil -convert xml1` first, so
// the decoding below is XML only, and the tests can hand it fixtures on any
// system.
func readPlist(path string) (any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if bytes.HasPrefix(b, []byte("bplist")) {
		out, err := exec.Command("plutil", "-convert", "xml1", "-o", "-", path).Output()
		if err != nil {
			return nil, fmt.Errorf("plutil could not convert %s: %w", path, err)
		}
		b = out
	}
	return decodePlistXML(b)
}

// decodePlistXML decodes an XML property list.
func decodePlistXML(b []byte) (any, error) {
	d := xml.NewDecoder(bytes.NewReader(b))
	for {
		tok, err := d.Token()
		if err != nil {
			return nil, fmt.Errorf("no <plist> element: %w", err)
		}
		if se, ok := tok.(xml.StartElement); ok && se.Name.Local == "plist" {
			for {
				tok, err := d.Token()
				if err != nil {
					return nil, err
				}
				switch t := tok.(type) {
				case xml.StartElement:
					return plistValue(d, t)
				case xml.EndElement:
					return nil, errors.New("empty <plist>")
				}
			}
		}
	}
}

func plistValue(d *xml.Decoder, se xml.StartElement) (any, error) {
	switch se.Name.Local {
	case "dict":
		m := map[string]any{}
		key := ""
		haveKey := false
		for {
			tok, err := d.Token()
			if err != nil {
				return nil, err
			}
			switch t := tok.(type) {
			case xml.StartElement:
				if t.Name.Local == "key" {
					k, err := plistText(d)
					if err != nil {
						return nil, err
					}
					key, haveKey = k, true
					continue
				}
				if !haveKey {
					return nil, fmt.Errorf("<%s> in a <dict> with no <key> before it", t.Name.Local)
				}
				v, err := plistValue(d, t)
				if err != nil {
					return nil, err
				}
				m[key] = v
				haveKey = false
			case xml.EndElement:
				return m, nil
			}
		}
	case "array":
		var a []any
		for {
			tok, err := d.Token()
			if err != nil {
				return nil, err
			}
			switch t := tok.(type) {
			case xml.StartElement:
				v, err := plistValue(d, t)
				if err != nil {
					return nil, err
				}
				a = append(a, v)
			case xml.EndElement:
				return a, nil
			}
		}
	case "true", "false":
		if err := d.Skip(); err != nil {
			return nil, err
		}
		return se.Name.Local == "true", nil
	}
	s, err := plistText(d)
	if err != nil {
		return nil, err
	}
	switch se.Name.Local {
	case "string":
		return s, nil
	case "integer":
		return strconv.ParseInt(strings.TrimSpace(s), 10, 64)
	case "real":
		return strconv.ParseFloat(strings.TrimSpace(s), 64)
	case "date":
		return time.Parse(time.RFC3339, strings.TrimSpace(s))
	case "data":
		return base64.StdEncoding.DecodeString(strings.Join(strings.Fields(s), ""))
	}
	return nil, fmt.Errorf("unknown plist element <%s>", se.Name.Local)
}

// plistText reads the character data up to the end of the current element.
func plistText(d *xml.Decoder) (string, error) {
	var sb strings.Builder
	for {
		tok, err := d.Token()
		if err != nil {
			return "", err
		}
		switch t := tok.(type) {
		case xml.CharData:
			sb.Write(t)
		case xml.EndElement:
			return sb.String(), nil
		case xml.StartElement:
			return "", fmt.Errorf("<%s> inside a text element", t.Name.Local)
		}
	}
}

// Typed lookups. Each answers its zero value when the key is absent or holds
// another type, which is how a check reads "not recorded".

func pDict(v any) map[string]any { m, _ := v.(map[string]any); return m }
func pArray(v any) []any         { a, _ := v.([]any); return a }
func pString(v any) string       { s, _ := v.(string); return s }

func pBool(v any) (val, ok bool) {
	b, ok := v.(bool)
	return b, ok
}

func pTime(v any) (time.Time, bool) {
	t, ok := v.(time.Time)
	return t, ok
}
