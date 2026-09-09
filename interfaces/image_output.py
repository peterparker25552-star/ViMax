import base64

from typing import List, Literal, Optional, Union
from PIL import Image

from utils.image import download_image



class ImageOutput:
    fmt: Literal["b64", "url", "pil", "np"]
    ext: str = "png"
    data: Union[str, Image.Image]

    def __init__(
        self,
        fmt: Literal["b64", "url", "pil", "np"],
        ext: str,
        data: Union[str, Image.Image],
    ):
        self.fmt = fmt
        self.ext = ext
        self.data = data


    def save_b64(self, path: str) -> None:
        """Save a base64 encoded image to the specified path.

        Args:
            path (str): Path where the image will be saved.
        """
        with open(path, 'wb') as f:
            f.write(base64.b64decode(self.data))

    def save_url(self, path: str) -> None:
        """Download and save an image from a URL to the specified path.

        Args:
            path (str): Path where the image will be saved.
        """
        download_image(self.data, path)

    def save_pil(self, path: str) -> None:
        """Save a PIL Image to the specified path.

        Args:
            path (str): Path where the image will be saved.
        """
        self.data.save(path)

    def save_np(self, path: str) -> None:
        """Save a numpy array to the specified path.

        Args:
            path (str): Path where the image will be saved.
        """
        # cv2 is only needed for the numpy-array flavour of ImageOutput;
        # import it lazily so lightweight installs (e.g. Termux on Android)
        # can use the b64/url/pil formats without OpenCV.
        try:
            import cv2
        except ImportError as error:
            raise RuntimeError(
                "Saving a numpy-array image requires OpenCV. "
                "Install it with: pip install opencv-python"
            ) from error
        cv2.imencode('.png', self.data)[1].tofile(path)

    def save(self, path: str) -> None:
        save_func = getattr(self, f"save_{self.fmt}")
        save_func(path)