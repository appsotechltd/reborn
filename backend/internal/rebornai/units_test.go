package rebornai

import "testing"

func TestVoiceUnits(t *testing.T) {
	for text, want := range map[string]int{"": 0, "one": 1, "a b c d e f g h i j k l m n o p q r s t u v w x y z a b c d": 1,
		"a b c d e f g h i j k l m n o p q r s t u v w x y z a b c d e": 2} {
		if got := VoiceUnits(text); got != want {
			t.Errorf("VoiceUnits(%q) = %d, want %d", text, got, want)
		}
	}
}

func TestSpoken(t *testing.T) {
	got := Spoken("**Wake** at the same time [nhs-sleep-tips--01].\n\n- Get light [meditations-marcus-aurelius--12]")
	if want := "Wake at the same time. - Get light"; got != want {
		t.Fatalf("Spoken = %q, want %q", got, want)
	}
}

func TestChartValidate(t *testing.T) {
	ok := Chart{Kind: "bar", Labels: []string{"a", "b"}, Series: []Series{{Name: "x", Values: []float64{1, 2}}}}
	if err := ok.validate(); err != nil {
		t.Fatal(err)
	}
	for _, c := range []Chart{
		{Kind: "radar", Labels: []string{"a"}, Series: []Series{{Values: []float64{1}}}},
		{Kind: "bar", Labels: []string{"a", "b"}, Series: []Series{{Values: []float64{1}}}},
		{Kind: "pie", Labels: []string{"a"}, Series: []Series{{Values: []float64{1}}, {Values: []float64{2}}}},
		{Kind: "pie", Labels: []string{"a"}, Series: []Series{{Values: []float64{-1}}}},
	} {
		if err := c.validate(); err == nil {
			t.Errorf("%+v passed", c)
		}
	}
}
