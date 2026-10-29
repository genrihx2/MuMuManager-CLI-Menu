package main

import (
	"encoding/json"
	"testing"
)

func TestSplitVerb(t *testing.T) {
	tests := []struct {
		in       []string
		verb     string
		rest     []string
		whitelist []string
	}{
		{[]string{}, "run", nil, nil},
		{[]string{"run"}, "run", nil, nil},
		{[]string{"run", "--once"}, "run", []string{"--once"}, nil},
		{[]string{"start", "--index", "2"}, "start", []string{"--index", "2"}, nil},
		{[]string{"start", "--restore"}, "start", []string{"--restore"}, nil},
		{[]string{"wait", "--index", "3", "--timeout", "30"}, "wait", []string{"--index", "3", "--timeout", "30"}, nil},
		{[]string{"status", "--deep"}, "status", []string{"--deep"}, nil},
		{[]string{"status", "--index", "1"}, "status", []string{"--index", "1"}, nil},
	}

	for _, tc := range tests {
		v, r, err := splitVerb(tc.in)
		if err != nil {
			t.Fatalf("splitVerb(%v) unexpected error: %v", tc.in, err)
		}
		if v != tc.verb {
			t.Errorf("splitVerb(%v) verb = %q, want %q", tc.in, v, tc.verb)
		}
		if !stringSliceEquals(r, tc.rest) {
			t.Errorf("splitVerb(%v) rest = %v, want %v", tc.in, r, tc.rest)
		}
		for _, w := range tc.whitelist {
			if v != w {
				t.Errorf("splitVerb(%v) verb %q not in whitelist %v", tc.in, v, tc.whitelist)
			}
		}
	}
}

func TestSplitVerbUnknown(t *testing.T) {
	_, _, err := splitVerb([]string{"bogus"})
	if err == nil {
		t.Error("splitVerb(bogus) expected error, got nil")
	}
	if !strings.Contains(err.Error(), "bogus") {
		t.Errorf("splitVerb(bogus) error = %q, expected mention of bogus", err.Error())
	}
}

func TestParsePositiveInt(t *testing.T) {
	tests := []struct {
		in    string
		want  int
	valid bool
	}{
		{"1", 1, true},
		{"120", 120, true},
		{"999", 999, true},
		{"0", 0, false},
		{"-1", -1, false},
		{"abc", 0, false},
		{"3.14", 0, false},
	}
	for _, tc := range tests {
		got, err := parsePositiveInt(tc.in)
		if tc.valid {
			if err != nil {
				t.Errorf("parsePositiveInt(%q) error = %v, expected none", tc.in, err)
			} else if got != tc.want {
				t.Errorf("parsePositiveInt(%q) = %d, want %d", tc.in, got, tc.want)
			}
		} else {
			if err == nil {
				t.Errorf("parsePositiveInt(%q) expected error, got %d", tc.in, got)
			}
		}
	}
}

func TestParseIndex(t *testing.T) {
	tests := []struct {
		in    string
		want  int
	valid bool
	}{
		{"1", 1, true},
		{"3", 3, true},
		{"0", 0, false},
		{"-1", -1, false},
	}
	for _, tc := range tests {
		got, err := parseIndex(tc.in)
		if tc.valid {
			if err != nil {
				t.Errorf("parseIndex(%q) error = %v, expected none", tc.in, err)
			} else if got != tc.want {
				t.Errorf("parseIndex(%q) = %d, want %d", tc.in, got, tc.want)
			}
		} else {
			if err == nil {
				t.Errorf("parseIndex(%q) expected error, got %d", tc.in, got)
			}
		}
	}
}

func TestStatusOutputShape(t *testing.T) {
	raw := `{"scriptVersion":"v10.3.5","muMuVersion":"10.3.5.0","instances":[{"index":"1","name":"Test","playerState":"start_finished","running":true,"androidStarted":true}]}`
	var st statusOutput
	if err := json.Unmarshal([]byte(raw), &st); err != nil {
		t.Fatalf("statusOutput unmarshal: %v", err)
	}
	if st.ScriptVersion != "v10.3.5" {
		t.Errorf("scriptVersion = %q, want %q", st.ScriptVersion, "v10.3.5")
	}
	if len(st.Instances) != 1 {
		t.Fatalf("instances count = %d, want 1", len(st.Instances))
	}
	inst := st.Instances[0]
	if inst.Index != "1" || inst.Name != "Test" || !inst.AndroidStarted {
		t.Errorf("instance = %+v, expected index=1 name=Test androidStarted=true", inst)
	}

	// Unknown fields must not break deserialisation.
	raw2 := `{"scriptVersion":"v10.3.5","muMuVersion":"10.3.5.0","instances":[],"extra":"ignore"}`
	if err := json.Unmarshal([]byte(raw2), &st); err != nil {
		t.Errorf("statusOutput with unknown field: %v", err)
	}
	if len(st.Instances) != 0 {
		t.Errorf("instances = %d, want 0", len(st.Instances))
	}
}

func stringSliceEquals(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
