# Document OCR Service

Small Cloud Run API for document OCR using Google Document AI.

## Endpoints

- `GET /health`
- `POST /ocr`

`POST /ocr` requires `X-API-Key`.

Multipart upload:

```powershell
curl.exe -X POST "$env:OCR_URL/ocr" `
  -H "X-API-Key: $env:OCR_API_KEY" `
  -F "file=@C:\path\to\image.png"
```

JSON upload:

```json
{
  "document_base64": "...",
  "mime_type": "application/pdf"
}
```

Supported input types depend on the configured Document AI OCR processor, including
PDFs and common scanned image formats.
