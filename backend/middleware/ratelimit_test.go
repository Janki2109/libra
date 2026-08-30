package middleware

import (
	"testing"
	"time"
)

func TestRateLimiterAllowsUpToCapacity(t *testing.T) {
	rl := NewRateLimiter(3, time.Minute)

	for i := 0; i < 3; i++ {
		if ok, _ := rl.Allow("1.2.3.4"); !ok {
			t.Fatalf("request %d was refused inside the limit", i+1)
		}
	}

	ok, retry := rl.Allow("1.2.3.4")
	if ok {
		t.Error("the 4th request was allowed past a capacity of 3")
	}
	if retry <= 0 {
		t.Error("a refusal must report a positive retry-after")
	}
}

func TestRateLimiterIsPerKey(t *testing.T) {
	rl := NewRateLimiter(1, time.Minute)

	if ok, _ := rl.Allow("1.1.1.1"); !ok {
		t.Fatal("first key refused on its first request")
	}
	// One client exhausting its bucket must not lock out everyone else.
	if ok, _ := rl.Allow("2.2.2.2"); !ok {
		t.Error("a second client was refused because of the first client's usage")
	}
}

func TestRateLimiterWindowResets(t *testing.T) {
	rl := NewRateLimiter(1, 40*time.Millisecond)

	if ok, _ := rl.Allow("1.1.1.1"); !ok {
		t.Fatal("first request refused")
	}
	if ok, _ := rl.Allow("1.1.1.1"); ok {
		t.Fatal("second request allowed inside the window")
	}

	time.Sleep(60 * time.Millisecond)

	if ok, _ := rl.Allow("1.1.1.1"); !ok {
		t.Error("the bucket did not reset after the window elapsed")
	}
}

func TestFormatSecondsIsWholeSeconds(t *testing.T) {
	// Retry-After is defined as an integer number of seconds; a Go duration
	// string like "1m0s" is not a valid header value.
	cases := map[time.Duration]string{
		90 * time.Second:       "90",
		time.Minute:            "60",
		time.Millisecond:       "1", // never zero or negative
		500 * time.Millisecond: "1",
	}
	for in, want := range cases {
		if got := formatSeconds(in); got != want {
			t.Errorf("formatSeconds(%v) = %q, want %q", in, got, want)
		}
	}
}
