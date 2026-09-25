"""Transcrit un wav avec le modele faster-whisper deja present (CyberScribe)."""
import sys

def main():
    if len(sys.argv) < 3:
        print("", end="")
        return 2
    model_dir = sys.argv[1]
    wav = sys.argv[2]
    from faster_whisper import WhisperModel
    model = WhisperModel(model_dir, device="cpu", compute_type="int8")
    segments, _info = model.transcribe(wav, language="fr", vad_filter=True)
    text = " ".join(s.text.strip() for s in segments if s.text and s.text.strip())
    sys.stdout.write(text.strip())
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
