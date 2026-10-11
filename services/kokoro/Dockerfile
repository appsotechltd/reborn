# Reborn's free speech service: Kokoro-82M (Apache-2.0) on the CPU.
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir "kokoro-onnx==0.6.1" "lameenc==1.8.4" \
 && python -c "import urllib.request as u; b='https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/'; [u.urlretrieve(b+f, f) for f in ('kokoro-v1.0.onnx', 'voices-v1.0.bin')]"
COPY server.py .
ENV KOKORO_MODEL=/app/kokoro-v1.0.onnx KOKORO_VOICES=/app/voices-v1.0.bin PORT=8880
EXPOSE 8880
CMD ["python", "server.py"]
