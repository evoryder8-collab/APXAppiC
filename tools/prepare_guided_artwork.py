"""Rebuild the offline iPhone artwork with Pillow, NumPy and OpenCV."""

import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'public/exercise-assets'
OUTPUT = ROOT / 'ios/APEXNative/APEX/Resources/GuidedArtwork'
EDGE = 720


def source_image(path, digest):
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f'{path}: source differs from reviewed manifest')
    with Image.open(path) as image:
        if image.mode != 'RGBA' or image.getchannel('A').getextrema()[0] != 0:
            raise ValueError(f'{path}: expected transparent artwork')
        return image.copy()


def visible_box(image):
    # Ignore near-invisible PNG noise when framing, and retain an antialiasing margin.
    left, top, right, bottom = image.getchannel('A').point(lambda a: 255 if a >= 8 else 0).getbbox()
    return max(0, left - 6), max(0, top - 6), min(image.width, right + 6), min(image.height, bottom + 6)


def separate(image, endpoint):
    alpha = np.asarray(image.getchannel('A'))
    _, labels, stats, centers = cv2.connectedComponentsWithStats((alpha >= 16).astype('uint8'))
    areas = stats[1:, cv2.CC_STAT_AREA]
    if len(areas) < 2:
        return None
    big, small = np.argsort(areas)[-2:][::-1] + 1
    if areas[small - 1] < areas[big - 1] / 3 or (areas.sum() - areas[big - 1] - areas[small - 1]) > areas.sum() * 0.025:
        return None
    axis = 0 if endpoint in ('left', 'right') else 1
    if abs(centers[big, axis] - centers[small, axis]) < image.size[axis] / 4:
        return None
    ordered = sorted((big, small), key=lambda label: centers[label, axis], reverse=endpoint in ('right', 'bottom'))
    distances = [cv2.distanceTransform((labels != label).astype('uint8'), cv2.DIST_L2, 3) for label in ordered]
    nearest = distances[0] <= distances[1]
    # A detached plate or prop must stay entirely with one figure.
    if np.intersect1d(np.unique(labels[nearest]), np.unique(labels[~nearest])).size > 1:
        return None
    poses = []
    for mask in (nearest, ~nearest):
        pose = image.copy()
        pose.putalpha(Image.fromarray(np.where(mask, alpha, 0).astype('uint8')))
        poses.append(pose.crop(visible_box(pose)))
    return poses


def save_frames(frames, paths):
    width = max(frame.width for frame in frames)
    height = max(frame.height for frame in frames)
    margin = max(2, round(max(width, height) * 0.025))
    for frame, path in zip(frames, paths):
        canvas = Image.new('RGBA', (width + 2 * margin, height + 2 * margin))
        canvas.paste(frame, (margin + (width - frame.width) // 2, margin + height - frame.height))
        canvas.thumbnail((EDGE, EDGE), Image.Resampling.LANCZOS)
        canvas.save(path, 'WEBP', quality=80, method=4, alpha_quality=85)
        with Image.open(path) as result:
            if result.mode != 'RGBA' or result.size != canvas.size or result.getchannel('A').getextrema()[0] != 0:
                raise ValueError(f'{path}: invalid encoded frame')


def main():
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    orientations = json.loads((ROOT / 'tools/exercise-pose-orientation.json').read_text())
    entries = manifest['entries']
    ids = {entry['id'] for entry in entries}
    if len(ids) != len(entries) or orientations.keys() - ids:
        raise ValueError('Duplicate source IDs or unknown pose orientations')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    cv2.setNumThreads(1)
    with TemporaryDirectory(dir=OUTPUT.parent) as temp:
        stage = Path(temp)

        def render(entry):
            key = entry['id']
            image = source_image(SOURCE / entry['file'], entry['sha256'])
            info = orientations.get(key)
            if info:
                if info['endpoint'] not in ('left', 'right', 'top', 'bottom') or info['first'] not in ('eccentric', 'concentric') or info['pause'] not in ('eccentric', 'concentric', 'mid'):
                    raise ValueError(f'{key}: invalid phase metadata')
                poses = separate(image, info['endpoint'])
                if poses:
                    save_frames(poses, [stage / f'{key}-{i}.webp' for i in (1, 2)])
                    return key, {'first': info['first'], 'pause': info['pause']}
            save_frames([image.crop(visible_box(image))], [stage / f'{key}.webp'])
            return None

        with ThreadPoolExecutor(max_workers=4) as workers:
            cadence = dict(result for result in workers.map(render, entries) if result)
        rest = manifest['supplemental_workout_assets']['breaktime']
        image = source_image(SOURCE / rest['file'], rest['sha256'])
        save_frames([image.crop(visible_box(image))], [stage / 'breaktime.webp'])
        (stage / 'cadence.json').write_text(json.dumps(cadence, indent=2, sort_keys=True) + '\n')
        if len(list(stage.glob('*.webp'))) != len(entries) + len(cadence) + 1:
            raise ValueError('Incomplete frame set')
        OUTPUT.mkdir(exist_ok=True)
        names = {file.name for file in stage.iterdir()}
        for file in stage.iterdir():
            file.replace(OUTPUT / file.name)
        for old in OUTPUT.glob('*.webp'):
            if old.name not in names:
                old.unlink()
    print(f'{len(entries)} exercises, {len(cadence)} separated pairs, 1 rest image')


if __name__ == '__main__':
    main()
