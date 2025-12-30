/**
 * Generates a QR code for KBZ Pay payments
 * This is a utility function that creates a simple SVG QR code representation
 * In a real implementation, you would use a proper QR code library
 */
export function generateKBZPayQRCode(orderId: string, amount: number): string {
  // In a real implementation, you would use a proper QR code library
  // For example: import QRCode from 'qrcode'
  // And generate the actual payment URL for KBZ Pay
  
  // For demonstration purposes, we'll return a placeholder SVG QR code
  // with encoded payment information
  const paymentData = `KBZPAY:${orderId}:${amount}`;
  
  // This is a simplified SVG representation of a QR code
  // In production, use a proper QR code library
  return `data:image/svg+xml;base64,${btoa(`
    <svg width="200" height="200" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <rect width="200" height="200" fill="#ffffff"/>
      <g fill="#000000">
        <rect x="10" y="10" width="40" height="40"/>
        <rect x="150" y="10" width="40" height="40"/>
        <rect x="10" y="150" width="40" height="40"/>
        <rect x="30" y="30" width="20" height="20"/>
        <rect x="160" y="30" width="20" height="20"/>
        <rect x="30" y="160" width="20" height="20"/>
        
        ${generateRandomQRPattern()}
        
        <text x="100" y="185" font-size="12" text-anchor="middle" fill="#000000">
          KBZ Pay: Order #${orderId.substring(0, 8)}
        </text>
      </g>
    </svg>
  `.trim())}`;
}

/**
 * Helper function to generate random pattern for QR code
 */
function generateRandomQRPattern(): string {
  let pattern = '';
  for (let i = 0; i < 50; i++) {
    const x = 20 + Math.floor(Math.random() * 160);
    const y = 20 + Math.floor(Math.random() * 160);
    const size = 5 + Math.floor(Math.random() * 10);
    
    // Avoid placing blocks in the alignment marker areas
    if (!((x < 60 && y < 60) || (x > 140 && y < 60) || (x < 60 && y > 140))) {
      pattern += `<rect x="${x}" y="${y}" width="${size}" height="${size}"/>`;
    }
  }
  return pattern;
}

/**
 * Generates a payment link for KBZ Pay
 */
export function generateKBZPayLink(orderId: string, amount: number, callbackUrl?: string): string {
  // In a real implementation, this would generate an actual KBZ Pay payment link
  // For now, we'll simulate it
  const params = new URLSearchParams({
    orderId,
    amount: amount.toString(),
    currency: 'MMK', // Myanmar Kyat
    ...(callbackUrl && { callback: callbackUrl })
  });
  
  return `kbzpay://payment?${params.toString()}`;
}