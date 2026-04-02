export interface CropBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

export const DEF_CROP: CropBox = { x: 0.1, y: 0.1, w: 0.8, h: 0.8 };

export type Screen =
  | 'home'
  | 'trimVideo'
  | 'cropImage'
  | 'cropVideo'
  | 'trimAndCropVideo';
