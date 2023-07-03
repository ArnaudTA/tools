import crypto from 'node:crypto'

// encryptionKey should have an exact length of 32 characters
const encryptionKey = 'a-key-with-exactly-32-characters' // process.env.ENCRYPTION_KEY
// for AES use 16 as ivLength
const ivLength = 16

/**
 * @function generateHash
 * @param {string} password - Password to hash.
 * @returns {promise} Hash of input password.
*/
export const generateHash = async (password) => {
  return new Promise((resolve, reject) => {
    const salt = crypto.randomBytes(8).toString('hex')
    crypto.scrypt(password, salt, 64, (err, derivedKey) => {
      if (err) {
        reject(err)
      }
      resolve(salt + ':' + derivedKey.toString('hex'))
    })
  })
}

/**
 * @function compareToHash
 * @param {string} password - Password to compare with hash.
 * @param {string} hash - Hash to compare with password.
 * @returns {promise} Equality of password and hash.
*/
export const compareToHash = async (password, hash) => {
  return new Promise((resolve, reject) => {
    const [salt, key] = hash.split(':')
    const keyBuffer = Buffer.from(key, 'hex')
    crypto.scrypt(password, salt, 64, (err, derivedKey) => {
      if (err) {
        reject(err)
      }
      resolve(crypto.timingSafeEqual(keyBuffer, derivedKey))
    })
  })
}

/**
 * @function encrypt
 * @param {string} text - Text to encrypt.
 * @returns {promise} Encrypted text.
*/
export const encrypt = (text) => {
  return new Promise((resolve, reject) => {
    try {
      const iv = crypto.randomBytes(ivLength)
      const cipher = crypto.createCipheriv('aes-256-cbc', Buffer.from(encryptionKey), iv)
      let encrypted = cipher.update(text)
      encrypted = Buffer.concat([encrypted, cipher.final()])
      resolve(iv.toString('hex') + ':' + encrypted.toString('hex'))
    } catch (err) {
      reject(err)
    }
  })
}

/**
 * @function decrypt
 * @param {string} text - Encrypted text to decrypt.
 * @returns {promise} Decrypted text.
*/
export const decrypt = (text) => {
  return new Promise((resolve, reject) => {
    try {
      const textParts = text.split(':')
      const iv = Buffer.from(textParts.shift(), 'hex')
      const encryptedText = Buffer.from(textParts.join(':'), 'hex')
      const decipher = crypto.createDecipheriv('aes-256-cbc', Buffer.from(encryptionKey), iv)
      let decrypted = decipher.update(encryptedText)
      decrypted = Buffer.concat([decrypted, decipher.final()])
      resolve(decrypted.toString())
    } catch (err) {
      reject(err)
    }
  })
}

/**
 * @function generateRandomPassword
 * @param {number} [length=24] - Length of the generated password.
 * @returns {string} Generated password.
*/
export const generateRandomPassword = (length = 24) => {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@-_#$*'
  return Array.from(crypto.getRandomValues(new Uint32Array(length)))
    .map((x) => chars[x % chars.length])
    .join('')
}

// Test functions
(async () => {
  const password = 'Password42!'

  const hash = await generateHash(password)
  const isHashEqual = await compareToHash(password, hash)

  const encrypted = await encrypt(password)
  const decrypted = await decrypt(encrypted)

  const generatedPassword = generateRandomPassword()

  console.log({ 
    password, 
    encryptionKey,
    hash,
    isHashEqual,
    encrypted, 
    decrypted,
    generatedPassword
  })
})()
